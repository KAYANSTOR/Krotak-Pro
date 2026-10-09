import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/application/incoming_sms_handler.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide
        AuditLog,
        Card,
        CardCategory,
        Customer,
        CustomerIdentifier,
        IncomingMessage,
        Sale,
        Transaction,
        TransferTemplate,
        AppSetting;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/advance.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';
import 'package:net_app/domain/services/local_advance_service.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/salafni_customer_ceiling.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/platform/sms_bridge.dart';

import '../helpers/trusted_payment_source.dart';

/// أمر سلفني بمبلغ محدد من مدخل المشغّل (نفس مسار SMS الواردة) حتى الإصدار:
/// مطابقة الفئة بنفس القيمة، رفض بلا بديل عند غياب الفئة أو مخزونها، وسقف
/// العميل. هذه هي معايير AC-C1..AC-C3 في تدقيق عقود المرحلة 0.
void main() {
  const currency = 'YER';

  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalMessageRepository messages;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalAuditLogRepository auditLogs;
  late LocalAdvanceRepository advances;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
  late LocalSettingsRepository settings;
  late LocalAdvanceService advanceService;
  late LocalTransferProcessor processor;
  late _RecordingSender sender;
  late IncomingSmsHandler handler;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    messages = LocalMessageRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    advances = LocalAdvanceRepository(transactions: transactions, sales: sales);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 10, 9, 9));
    ids = SequentialIdGenerator();

    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    balanceService = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    inventoryService = LocalCardInventoryService(
      categories: categories,
      cards: cards,
      unitOfWork: unitOfWork,
    );
    saleService = LocalSaleService(
      customers: customers,
      categories: categories,
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balanceService,
      inventory: inventoryService,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    settings = LocalSettingsRepository(database);
    final seeded = await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: clock,
    ).seedIfNeeded();
    expect(seeded, isA<Success<void>>());
    await settings.save(
      AppSetting(
        key: SettingKeys.salafniEnabled,
        value: 'true',
        updatedAt: clock.now(),
      ),
    );
    sender = _RecordingSender();
    advanceService = LocalAdvanceService(
      advances: advances,
      customers: customers,
      categories: categories,
      cards: cards,
      inventory: inventoryService,
      transactions: transactions,
      sales: sales,
      auditLogs: auditLogs,
      settings: settings,
      unitOfWork: unitOfWork,
      messageSender: sender,
      clock: clock,
      ids: ids,
    );
    processor = LocalTransferProcessor(
      messages: messages,
      customers: customers,
      balances: balanceService,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
      categories: categories,
      cards: cards,
      inventory: inventoryService,
      transactions: transactions,
      reservedSales: saleService,
      messageSender: sender,
      settings: settings,
      advanceService: advanceService,
    );
    handler = IncomingSmsHandler(
      bridge: _FakeSmsBridge(),
      messages: messages,
      parser: LocalMessageParser(templates: const []),
      processor: processor,
      ids: ids,
      sourceGuard: trustedPaymentSourceGuard(),
      settings: settings,
      advanceService: advanceService,
    );
  });

  Future<Customer> seedCustomer(String phone) async {
    final created = await customerService.create(
      displayName: 'عميل سلفني',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    return (created as Success<Customer>).value;
  }

  Future<void> seedCategory({
    required int minorUnits,
    required String categoryId,
    int cardCount = 2,
  }) async {
    final saved = await catalogService.saveCategory(
      CardCategory(
        id: categoryId,
        name: 'فئة $minorUnits',
        faceValue: Money(minorUnits: minorUnits, currencyCode: currency),
        isActive: true,
      ),
    );
    expect(saved, isA<Success<CardCategory>>());
    if (cardCount == 0) return;
    final imported = await catalogService.importCards(
      categoryId: categoryId,
      drafts: [
        for (var i = 0; i < cardCount; i++)
          CardImportDraft(
            serialNumber: 'SN-$categoryId-$i',
            secretCode: 'PIN-$categoryId-$i',
          ),
      ],
    );
    expect(imported, isA<Success<int>>());
  }

  Future<int> soldCards(String categoryId) async {
    final rows = await cards.findByCategory(categoryId);
    return (rows as Success<List<Card>>)
        .value
        .where((card) => card.status == CardStatus.sold)
        .length;
  }

  Future<List<Advance>> advancesOf(String customerId) async {
    final rows = await advanceService.listCustomerAdvances(customerId);
    return (rows as Success<List<Advance>>).value;
  }

  test('سلفني 200 issues the matching category and sends the card', () async {
    final customer = await seedCustomer('733222111');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');

    final result = await handler.handleManual(
      sender: '733222111',
      body: 'سلفني 200',
    );

    expect(result, isA<Success<Transaction?>>());
    final advances = await advancesOf(customer.id);
    expect(advances, hasLength(1));
    expect(advances.single.amount.minorUnits, 20000);
    expect(advances.single.outstanding.minorUnits, 20000);
    expect(await soldCards('cat-200'), 1);
    expect(sender.bodies, hasLength(1));
    expect(sender.bodies.single, contains('SN-cat-200-0'),
        reason: 'رسالة القبول تحمل رقم الكرت المصروف');
  });

  test('سلفني with eastern digits resolves the same category', () async {
    await seedCustomer('733222222');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');

    final result = await handler.handleManual(
      sender: '733222222',
      body: 'سلفني ٢٠٠',
    );

    expect(result, isA<Success<Transaction?>>());
    expect(await soldCards('cat-200'), 1);
  });

  test('سلفني 250 without a matching category is refused and sells nothing',
      () async {
    final customer = await seedCustomer('733222333');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');

    final result = await handler.handleManual(
      sender: '733222333',
      body: 'سلفني ٢٥٠',
    );

    expect(result, isA<Failure<Transaction?>>());
    expect((result as Failure<Transaction?>).error.code,
        'salafni_category_mismatch',
        reason: 'لا تُستبدل الفئة بأصغر أو أكبر');
    expect(await soldCards('cat-200'), 0);
    expect(await advancesOf(customer.id), isEmpty);
    expect(sender.bodies, hasLength(1),
        reason: 'رسالة رفض واحدة، بلا نص كرت');
    expect(sender.bodies.single, contains('لا توجد فئة مطابقة'));
    expect(sender.bodies.single, isNot(contains('SN-cat-200')));
  });

  test('a matching category with no stock is refused by name', () async {
    await seedCustomer('733222444');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200', cardCount: 0);

    final result = await handler.handleManual(
      sender: '733222444',
      body: 'سلفني 200',
    );

    expect(result, isA<Failure<Transaction?>>());
    expect(
      (result as Failure<Transaction?>).error.code,
      'salafni_category_out_of_stock',
    );
    expect(sender.bodies, hasLength(1));
    expect(sender.bodies.single, contains('الفئة المطابقة بلا مخزون'));
  });

  test('the per-customer ceiling blocks an issue above it', () async {
    final customer = await seedCustomer('733222555');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');
    await settings.save(
      AppSetting(
        key: SalafniCustomerCeiling.key,
        value: SalafniCustomerCeiling.encode({customer.id: 5000}),
        updatedAt: clock.now(),
      ),
    );

    final result = await handler.handleManual(
      sender: '733222555',
      body: 'سلفني 200',
    );

    expect(result, isA<Failure<Transaction?>>());
    expect((result as Failure<Transaction?>).error.code,
        'salafni_ceiling_exceeded');
    expect(await soldCards('cat-200'), 0);
  });

  test('the bare command keeps issuing the smallest available category',
      () async {
    await seedCustomer('733222666');
    await seedCategory(minorUnits: 10000, categoryId: 'cat-100');
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');

    final result = await handler.handleManual(
      sender: '733222666',
      body: 'سلفني',
    );

    expect(result, isA<Success<Transaction?>>());
    expect(await soldCards('cat-100'), 1);
    expect(await soldCards('cat-200'), 0);
  });
}

final class _RecordingSender implements MessageSender {
  final List<String> bodies = <String>[];

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    bodies.add(body);
    return const Success<void>(null);
  }
}

final class _FakeSmsBridge extends SmsBridge {
  @override
  Future<List<IncomingSmsEvent>> peekPendingSms() async =>
      const <IncomingSmsEvent>[];

  @override
  Future<void> ackPendingSms(List<String> ids) async {}
}


  tearDown(() async => database.close());
