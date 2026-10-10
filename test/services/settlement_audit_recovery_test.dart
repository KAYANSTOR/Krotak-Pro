import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage, Wallet;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_message_recovery_service.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_settlement_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/payment_source_guard.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalMessageRepository messages;
  late LocalAuditLogRepository auditLogs;
  late LocalWalletRepository wallets;
  late LocalTransferTemplateRepository transferTemplates;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
  late LocalSettlementService settlementService;
  late LocalMessageParser parser;
  late LocalTransferProcessor processor;
  late LocalMessageRecoveryService recoveryService;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    messages = LocalMessageRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    wallets = LocalWalletRepository(database);
    transferTemplates = LocalTransferTemplateRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 1, 1, 12));
    ids = SequentialIdGenerator();

    await wallets.save(
      Wallet(
        id: 'wallet-bank',
        name: 'Bank SMS',
        status: WalletStatus.active,
        createdAt: clock.now(),
        senderId: 'BANK',
        sourceMode: WalletSourceMode.sms,
      ),
    );
    await transferTemplates.save(
      const TransferTemplate(
        id: 'tpl-1',
        name: 'default',
        pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
        isActive: true,
        walletId: 'wallet-bank',
      ),
    );

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
    settlementService = LocalSettlementService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    parser = LocalMessageParser(
      templates: const [
        TransferTemplate(
          id: 'tpl-1',
          name: 'default',
          pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
          isActive: true,
          walletId: 'wallet-bank',
        ),
      ],
    );
    processor = LocalTransferProcessor(
      messages: messages,
      customers: customers,
      balances: balanceService,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    recoveryService = LocalMessageRecoveryService(
      messages: messages,
      parser: parser,
      processor: processor,
      sourceGuard: PaymentSourceGuard(
        wallets: wallets,
        templates: transferTemplates,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> createCustomer({String phone = '770111222'}) async {
    final result = await customerService.create(
      displayName: 'عميل',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: phone,
    );
    return (result as Success<Customer>).value;
  }

  test('sale writes audit log for sold card and sale entity', () async {
    final customer = await createCustomer();
    await catalogService.saveCategory(
      CardCategory(
        id: 'cat-1',
        name: 'فئة',
        faceValue: const Money(minorUnits: 50000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    await catalogService.importCards(
      categoryId: 'cat-1',
      drafts: const [CardImportDraft(serialNumber: 'S-1', secretCode: 'pin')],
    );
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 50000, currencyCode: 'YER'),
      reference: 'dep-1',
    );

    final sold = await saleService.sellFromBalance(
      customerId: customer.id,
      categoryId: 'cat-1',
    );
    expect(sold, isA<Success<Sale>>());
    final sale = (sold as Success<Sale>).value;

    final saleAudit = await auditLogs.findByEntity('sale', sale.id);
    expect(saleAudit, isA<Success<List>>());
    expect((saleAudit as Success).value, isNotEmpty);
  });

  test('settlement debits balance idempotently by reference', () async {
    final customer = await createCustomer(phone: '770333444');
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 100000, currencyCode: 'YER'),
      reference: 'in-1',
    );

    final first = await settlementService.settle(
      customerId: customer.id,
      amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
      reference: 'settle-1',
    );
    expect(first, isA<Success<Transaction>>());

    final second = await settlementService.settle(
      customerId: customer.id,
      amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
      reference: 'settle-1',
    );
    expect(second, isA<Success<Transaction>>());
    expect(
      (second as Success<Transaction>).value.id,
      (first as Success<Transaction>).value.id,
    );

    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    expect((balance as Success<Money>).value.minorUnits, 60000);
  });

  test('settlement rejects insufficient balance', () async {
    final customer = await createCustomer(phone: '770555666');
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
    );

    final result = await settlementService.settle(
      customerId: customer.id,
      amount: const Money(minorUnits: 5000, currencyCode: 'YER'),
    );
    expect((result as Failure<Transaction>).error.code, 'insufficient_balance');
  });

  group('تأكيد سداد دين العميل — قرارات المالك §7', () {
    late _MemSettings noticeSettings;
    late _MemSender sender;
    late LocalSettlementService notifying;

    setUp(() {
      noticeSettings = _MemSettings(<String, String>{
        ...OutboundTemplateCatalog.initialBodies(),
      });
      sender = _MemSender();
      notifying = LocalSettlementService(
        customers: customers,
        transactions: transactions,
        auditLogs: auditLogs,
        unitOfWork: unitOfWork,
        clock: clock,
        ids: ids,
        settings: noticeSettings,
        messageSender: sender,
      );
    });

    test('sends the registered debt template with the real transaction values',
        () async {
      final customer = await createCustomer(phone: '770999888');
      await balanceService.credit(
        customerId: customer.id,
        amount: const Money(minorUnits: 100000, currencyCode: 'YER'),
        reference: 'in-notice-1',
      );

      final result = await notifying.settle(
        customerId: customer.id,
        amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
        reference: 'settle-notice-1',
      );

      expect(result, isA<Success<Transaction>>());
      expect(sender.destinations, <String>['770999888']);
      expect(sender.bodies, hasLength(1));
      // المبالغ من نتيجة المعاملة الفعلية: مسدد 400 والرصيد الجديد 600.
      expect(sender.bodies.single, contains('400'));
      expect(sender.bodies.single, contains('600'));

      final audit = await auditLogs.findByEntity(
        'transaction',
        (result as Success<Transaction>).value.id,
      );
      expect(
        (audit as Success<List<AuditLog>>)
            .value
            .any((entry) => entry.action == 'customer_debt_settlement_notified'),
        isTrue,
      );
    });

    test('never sends the notice twice for the same transaction', () async {
      final customer = await createCustomer(phone: '770888777');
      await balanceService.credit(
        customerId: customer.id,
        amount: const Money(minorUnits: 100000, currencyCode: 'YER'),
        reference: 'in-notice-2',
      );

      await notifying.settle(
        customerId: customer.id,
        amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
        reference: 'settle-notice-2',
      );
      await notifying.settle(
        customerId: customer.id,
        amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
        reference: 'settle-notice-2',
      );

      expect(sender.bodies, hasLength(1));
    });

    test('a failed notice never rolls back the settlement', () async {
      final failing = _MemSender(fail: true);
      final service = LocalSettlementService(
        customers: customers,
        transactions: transactions,
        auditLogs: auditLogs,
        unitOfWork: unitOfWork,
        clock: clock,
        ids: ids,
        settings: noticeSettings,
        messageSender: failing,
      );
      final customer = await createCustomer(phone: '770777666');
      await balanceService.credit(
        customerId: customer.id,
        amount: const Money(minorUnits: 100000, currencyCode: 'YER'),
        reference: 'in-notice-3',
      );

      final result = await service.settle(
        customerId: customer.id,
        amount: const Money(minorUnits: 40000, currencyCode: 'YER'),
        reference: 'settle-notice-3',
      );

      expect(result, isA<Success<Transaction>>());
      final balance = await balanceService.getBalance(
        customerId: customer.id,
        currencyCode: 'YER',
      );
      expect((balance as Success<Money>).value.minorUnits, 60000);
      final audit = await auditLogs.findByEntity(
        'transaction',
        (result as Success<Transaction>).value.id,
      );
      expect(
        (audit as Success<List<AuditLog>>)
            .value
            .any((entry) => entry.action == 'customer_debt_settlement_notify_failed'),
        isTrue,
      );
    });
  });

  test('message recovery processes pending SMS transfers once', () async {
    final customer = await createCustomer(phone: '770123456');
    final body = 'تم تحويل 1500 ريال الى 770123456 برقم العملية REF-77';
    final msg = IncomingMessage(
      id: ids.next('msg'),
      sender: 'BANK',
      body: body,
      receivedAt: clock.now(),
      status: MessageProcessingStatus.received,
      externalReference: 'ext-1',
    );
    await messages.save(msg);

    final report1 = await recoveryService.recoverPending();
    expect(report1, isA<Success<MessageRecoveryReport>>());
    expect((report1 as Success<MessageRecoveryReport>).value.processed, 1);

    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );

    expect((balance as Success<Money>).value.minorUnits, 150000);

    final report2 = await recoveryService.recoverPending();
    expect((report2 as Success<MessageRecoveryReport>).value.processed, 0);
  });

  test('expired card reservation returns to available stock', () async {
    await catalogService.saveCategory(
      CardCategory(
        id: 'cat-exp',
        name: 'فئة',
        faceValue: const Money(minorUnits: 1000, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    await catalogService.importCards(
      categoryId: 'cat-exp',
      drafts: const [CardImportDraft(serialNumber: 'E-1', secretCode: 'x')],
    );

    final reserved = await inventoryService.reserveAvailableCard(
      categoryId: 'cat-exp',
      reservationId: 'res-1',
      now: clock.now(),
      expiresAt: clock.now().subtract(const Duration(minutes: 1)),
    );
    expect(reserved, isA<Success<Card>>());

    final released = await cards.expireReservations(clock.now());
    expect((released as Success<int>).value, greaterThanOrEqualTo(1));

    final available = await cards.findAvailableByCategory('cat-exp');
    expect((available as Success<List<Card>>).value, hasLength(1));
  });
}

/// إعدادات في الذاكرة لقوالب الرسائل — المصدر الوحيد للنص وقت الإرسال.
final class _MemSettings implements SettingsRepository {
  _MemSettings([Map<String, String>? values])
      : values = values ?? <String, String>{};

  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    return Success(
      value == null
          ? null
          : AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _MemSender implements MessageSender {
  _MemSender({this.fail = false});

  final bool fail;
  final List<String> destinations = <String>[];
  final List<String> bodies = <String>[];

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    destinations.add(destination);
    bodies.add(body);
    if (fail) {
      return const Failure(
        AppFailure(code: 'sms_failed', message: 'SMS gateway rejected'),
      );
    }
    return const Success(null);
  }
}
