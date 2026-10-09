import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide
        Customer,
        Card,
        Sale,
        CardCategory,
        Transaction,
        IncomingMessage,
        AuditLog,
        AppSetting;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/advance.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';
import 'package:net_app/domain/services/local_advance_service.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';

/// مسار الإيداع مقابل دين سلفني على قاعدة Drift الحقيقية:
/// - السداد الكامل لا يبيع كرتًا ولا يرسل نص كرت.
/// - السداد الجزئي يحفظ الباقي رصيدًا بمرجع `salafni-surplus:` بلا كرت.
/// - الإيداع بلا كرت مطابق يُرسل قالب «إيداع بلا كرت» بلا حجز ولا بيع.
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
  late _RecordingMessageSender sender;
  late LocalTransferProcessor processor;

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
    clock = FixedClock(DateTime(2026, 10, 9, 12));
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
    sender = _RecordingMessageSender();
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
  });

  tearDown(() async => database.close());


  Future<Customer> seedCustomer() async {
    final result = await customerService.create(
      displayName: 'Ali Hassan',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000000',
    );
    return (result as Success<Customer>).value;
  }

  Future<void> seedAdvance({
    required String id,
    required String customerId,
    required int amountMinor,
  }) async {
    final amount = Money(minorUnits: amountMinor, currencyCode: currency);
    await transactions.append(
      Transaction(
        id: id,
        type: TransactionType.advance,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now().subtract(const Duration(hours: 2)),
        customerId: customerId,
        reference: 'salafni:$id',
      ),
    );
    await sales.save(
      Sale(
        id: id,
        customerId: customerId,
        cardId: 'card-$id',
        amount: amount,
        status: TransactionStatus.completed,
        createdAt: clock.now().subtract(const Duration(hours: 2)),
      ),
    );
  }

  Future<void> seedCategory({
    required int minorUnits,
    required String categoryId,
    bool withCard = true,
  }) async {
    final category = await catalogService.saveCategory(
      CardCategory(
        id: categoryId,
        name: 'Value $minorUnits',
        faceValue: Money(minorUnits: minorUnits, currencyCode: currency),
        isActive: true,
      ),
    );
    expect(category, isA<Success<CardCategory>>());
    if (!withCard) return;
    final imported = await catalogService.importCards(
      categoryId: categoryId,
      drafts: [
        CardImportDraft(
          serialNumber: 'SN-$categoryId',
          secretCode: 'SECRET-$categoryId',
        ),
      ],
    );
    expect(imported, isA<Success<int>>());
  }

  Future<void> seedMessage(String id) async {
    final saved = await messages.save(
      IncomingMessage(
        id: id,
        sender: 'Jaib',
        body: 'اضيف 200',
        receivedAt: clock.now(),
        status: MessageProcessingStatus.parsed,
        externalReference: 'Jaib:REF-$id',
        customerIdentifier: '733000000',
      ),
    );
    expect(saved, isA<Success<void>>());
  }

  ParsedTransfer transfer(String id, int amount) => ParsedTransfer(
        messageId: id,
        amount: Money(minorUnits: amount, currencyCode: currency),
        customerIdentifier: '733000000',
        identifierType: TransferIdentifierType.phone,
        reference: 'REF-$id',
      );

  Future<int> balanceOf(String customerId) async {
    final result = await balanceService.getBalance(
      customerId: customerId,
      currencyCode: currency,
    );
    return (result as Success<Money>).value.minorUnits;
  }


  test(
      'a deposit fully consumed by the advance sells no card and sends no card body',
      () async {
    final customer = await seedCustomer();
    await seedCategory(minorUnits: 10000, categoryId: 'cat-100');
    await seedAdvance(
      id: 'adv-full',
      customerId: customer.id,
      amountMinor: 10000,
    );
    await seedMessage('m-full');

    final result = await processor.process(transfer('m-full', 10000));

    expect(result, isA<Success<Transaction>>());
    final available = await cards.findAvailableByCategory('cat-100');
    expect((available as Success<List<Card>>).value, hasLength(1),
        reason: 'المبلغ المستخدم في السداد لا يحجز كرتًا');
    expect(await balanceOf(customer.id), 0);
    final saved = await messages.findById('m-full');
    expect((saved as Success<IncomingMessage?>).value?.status,
        MessageProcessingStatus.processed);
    expect(sender.bodies.any((body) => body.contains('SN-cat-100')), isFalse,
        reason: 'لا يُرسل نص كرت عند السداد الكامل');
    final advancesResult = await advanceService.listCustomerAdvances(customer.id);
    final open = (advancesResult as Success<List<Advance>>)
        .value
        .where((advance) => advance.outstanding.minorUnits > 0);
    expect(open, isEmpty, reason: 'الدين سُدَّد بالكامل');
  });

  test(
      'a partial settlement holds the surplus as balance and never buys a card',
      () async {
    final customer = await seedCustomer();
    // الباقي بعد السداد يطابق فئة نشطة واحدة، وهو شرط مسار السداد الحالي.
    await seedCategory(minorUnits: 15000, categoryId: 'cat-150');
    await seedAdvance(
      id: 'adv-part',
      customerId: customer.id,
      amountMinor: 5000,
    );
    await seedMessage('m-part');

    final result = await processor.process(transfer('m-part', 20000));

    expect(result, isA<Success<Transaction>>());
    final surplus =
        await transactions.findByReference('salafni-surplus:REF-m-part');
    expect((surplus as Success<Transaction?>).value?.amount.minorUnits, 15000,
        reason: 'الباقي يُحفظ رصيدًا بمرجع ثابت');
    expect(await balanceOf(customer.id), 15000);
    final available = await cards.findAvailableByCategory('cat-150');
    expect((available as Success<List<Card>>).value, hasLength(1),
        reason: 'الباقي لا يشتري كرتًا قبل قرار المالك');
    expect(sender.bodies.any((body) => body.contains('SN-cat-150')), isFalse);
    final audits = await auditLogs.findByEntity('message', 'm-part');
    expect(
      (audits as Success<List<AuditLog>>)
          .value
          .any((item) => item.action == 'salafni_surplus_held_as_balance'),
      isTrue,
    );
    final saved = await messages.findById('m-part');
    expect((saved as Success<IncomingMessage?>).value?.status,
        MessageProcessingStatus.processed);

    // إعادة المعالجة لا تكرر القيد ولا تفتح مسار الكرت.
    final replay = await processor.process(transfer('m-part', 20000));
    expect(replay, isA<Failure<Transaction>>());
    expect(await balanceOf(customer.id), 15000);
    final replayAvailable = await cards.findAvailableByCategory('cat-150');
    expect((replayAvailable as Success<List<Card>>).value, hasLength(1));
  });


  test(
      'a surplus that matches no active category still settles the debt first',
      () async {
    final customer = await seedCustomer();
    // الإيداع يطابق فئة الكرت، والباقي بعد الدين (150) لا يطابق أي فئة نشطة.
    await seedCategory(minorUnits: 20000, categoryId: 'cat-200');
    await seedAdvance(
      id: 'adv-mixed',
      customerId: customer.id,
      amountMinor: 5000,
    );
    await seedMessage('m-mixed');

    final result = await processor.process(transfer('m-mixed', 20000));

    // قرار المالك 2026-10-09 (§1): السداد أولًا دائمًا، والفائض رصيد، ولا كرت.
    expect(result, isA<Success<Transaction>>());
    final advancesResult =
        await advanceService.listCustomerAdvances(customer.id);
    final open = (advancesResult as Success<List<Advance>>)
        .value
        .where((advance) => advance.outstanding.minorUnits > 0);
    expect(open, isEmpty, reason: 'الدين يُسدَّد أولًا ولو لم يطابق الباقي فئة');
    final surplus =
        await transactions.findByReference('salafni-surplus:REF-m-mixed');
    expect((surplus as Success<Transaction?>).value?.amount.minorUnits, 15000,
        reason: 'الفائض يُحفظ رصيدًا بمرجع ثابت');
    expect(await balanceOf(customer.id), 15000);
    final available = await cards.findAvailableByCategory('cat-200');
    expect((available as Success<List<Card>>).value, hasLength(1),
        reason: 'لا يُشترى كرت من الفائض');
    expect(sender.bodies.any((body) => body.contains('SN-cat-200')), isFalse);
    final saved = await messages.findById('m-mixed');
    expect((saved as Success<IncomingMessage?>).value?.status,
        MessageProcessingStatus.processed);
  });

  test(
      'a deposit with no matching stock notifies the customer with the no-stock template',
      () async {
    await seedCustomer();
    await seedCategory(
      minorUnits: 20000,
      categoryId: 'cat-200',
      withCard: false,
    );
    await seedMessage('m-nostock');

    final result = await processor.process(transfer('m-nostock', 20000));

    expect((result as Failure<Transaction>).error.code, 'out_of_stock');
    final available = await cards.findAvailableByCategory('cat-200');
    expect((available as Success<List<Card>>).value, isEmpty);
    expect(sender.bodies, hasLength(1));
    expect(sender.bodies.single, contains('Ali'),
        reason: 'اسم الزبون الأول في قالب عدم توفر الكرت');
    expect(sender.bodies.single, contains('200'),
        reason: 'المبلغ بالوحدة الكبرى بلا كسور عشرية زائدة');
    final audits = await auditLogs.findByEntity('message', 'm-nostock');
    expect(
      (audits as Success<List<AuditLog>>)
          .value
          .any((item) => item.action == 'deposit_no_stock_notified'),
      isTrue,
    );
  });
}

final class _RecordingMessageSender implements MessageSender {
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
