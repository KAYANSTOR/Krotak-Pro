import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
        TransferTemplate;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';
import 'package:net_app/domain/services/default_pos_templates_seeder.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_message_retry_service.dart';
import 'package:net_app/domain/services/local_pos_account_registry.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/pos_order_delivery_worker.dart';
import 'package:net_app/domain/services/services.dart';

/// تنفيذ فعلي كامل لمسار طلب كروت نقطة البيع (بدون أي منطق وهمي):
/// SMS → تحليل → هوية نقطة البيع → اختيار الفئة → حجز المخزون → بيع الكرت →
/// قيد مالي على حساب نقطة البيع → رسالة العميل + رسالة تأكيد نقطة البيع → تدقيق.
///
/// كل شيء حقيقي: قاعدة Drift، الخدمات الفعلية، القوالب الفعلية، ومحرك التحليل.
void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalMessageRepository messages;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalAuditLogRepository audits;
  late LocalSettingsRepository settings;
  late LocalTransferTemplateRepository templates;
  late DriftUnitOfWork uow;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
  late LocalPosAccountRegistry posRegistry;
  late LocalMessageRetryService retryService;
  late LocalMessageParser parser;
  late _RecordingSender sender;
  late LocalTransferProcessor processor;
  late PosOrderDeliveryWorker worker;

  const posId = 'pos-1';
  const posPhone = '779000111';
  const posNotifyPhone = '777999888';
  const customerPhone = '779776919';
  const categoryId = 'cat-100';
  late String posLedgerCustomerId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    messages = LocalMessageRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    audits = LocalAuditLogRepository(database);
    settings = LocalSettingsRepository(database);
    templates = LocalTransferTemplateRepository(database);
    uow = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 24, 10));
    ids = SequentialIdGenerator();
    final outboundSeeded = await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: clock,
    ).seedIfNeeded();
    expect(outboundSeeded, isA<Success<void>>());

    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    balanceService = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    inventoryService = LocalCardInventoryService(
      categories: categories,
      cards: cards,
      unitOfWork: uow,
    );
    saleService = LocalSaleService(
      customers: customers,
      categories: categories,
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balanceService,
      inventory: inventoryService,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    posRegistry = LocalPosAccountRegistry(settings: settings, clock: clock);
    retryService = LocalMessageRetryService(
      auditLogs: audits,
      messages: messages,
      clock: clock,
      ids: ids,
    );

    // حساب نقطة البيع = عميل دفتر يحمل الدين.
    final posCustomer = await customerService.create(
      displayName: 'حساب نقطة صنعاء',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '777100200',
    );
    posLedgerCustomerId = (posCustomer as Success<Customer>).value.id;

    await posRegistry.save(
      PosAccount(
        posId: posId,
        customerId: posLedgerCustomerId,
        name: 'نقطة صنعاء',
        identifiers: const [posPhone],
        notifyPhone: posNotifyPhone,
        percentageMode: PosPercentageMode.defaultCategory,
      ),
    );

    // قوالب نقطة البيع الفعلية (ثلاثة قوالب واردة).
    final seeded = await DefaultPosTemplatesSeeder(templates: templates)
        .seedForPos(posId: posId, posName: 'نقطة صنعاء');
    expect(seeded, isA<Success<int>>());

    final allTemplates = await templates.listAll();
    parser = LocalMessageParser(
      templates: (allTemplates as Success<List<TransferTemplate>>).value,
    );

    sender = _RecordingSender();
    processor = LocalTransferProcessor(
      messages: messages,
      customers: customers,
      balances: balanceService,
      auditLogs: audits,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
      categories: categories,
      cards: cards,
      inventory: inventoryService,
      transactions: transactions,
      reservedSales: saleService,
      messageSender: sender,
      settings: settings,
      posRegistry: posRegistry,
      sales: sales,
    );
    worker = PosOrderDeliveryWorker(
      messages: messages,
      auditLogs: audits,
      cards: cards,
      settings: settings,
      posRegistry: posRegistry,
      messageSender: sender,
      retryService: retryService,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async => database.close());

  Future<void> seedCategory({int minorUnits = 10000}) async {
    final saved = await catalogService.saveCategory(
      CardCategory(
        id: categoryId,
        name: 'فئة 100',
        faceValue: Money(minorUnits: minorUnits, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    expect(saved, isA<Success<CardCategory>>());
  }

  Future<void> seedCards(int count) async {
    final imported = await catalogService.importCards(
      categoryId: categoryId,
      drafts: [
        for (var i = 0; i < count; i++)
          CardImportDraft(
            serialNumber: 'SN-$categoryId-$i',
            secretCode: 'PIN-$categoryId-$i',
          ),
      ],
    );
    expect(imported, isA<Success<int>>());
    expect((imported as Success<int>).value, count);
  }

  /// Saves the inbound SMS exactly as the native bridge would deliver it.
  Future<IncomingMessage> saveInbound({
    required String id,
    required String body,
    String senderPhone = posPhone,
  }) async {
    final message = IncomingMessage(
      id: id,
      sender: senderPhone,
      body: body,
      receivedAt: clock.now(),
      status: MessageProcessingStatus.received,
    );
    final saved = await messages.save(message);
    expect(saved, isA<Success<void>>());
    return message;
  }

  /// Full ingress path: real parser on the persisted message.
  Future<ParsedTransfer> parseInbound(IncomingMessage message) async {
    final parsed = parser.parse(message);
    expect(
      parsed,
      isA<Success<ParsedTransfer>>(),
      reason: 'POS inbound template must match ${message.body}',
    );
    return (parsed as Success<ParsedTransfer>).value;
  }

  Future<void> processInbound(IncomingMessage message) async {
    final parsed = await parseInbound(message);
    final result = await processor.process(parsed);
    expect(
      result,
      isA<Success<Transaction>>(),
      reason: 'POS order must complete: '
          '${result is Failure<Transaction> ? result.error.code : ''}',
    );
  }

  Future<int> soldCardCount() async {
    final rows = await cards.findByCategory(categoryId);
    return (rows as Success<List<Card>>).value
        .where((c) => c.status == CardStatus.sold)
        .length;
  }

  Future<List<Transaction>> posLedger() async {
    final rows = await transactions.findByCustomer(posLedgerCustomerId);
    return (rows as Success<List<Transaction>>).value;
  }

  Future<int> posBalanceMinor() async {
    final balance = await balanceService.getBalance(
      customerId: posLedgerCustomerId,
      currencyCode: 'YER',
    );
    return (balance as Success<Money>).value.minorUnits;
  }

  Future<List<AuditLog>> messageAudits(String messageId, String action) async {
    final logs = await audits.findByEntity('message', messageId);
    return (logs as Success<List<AuditLog>>)
        .value
        .where((log) => log.action == action)
        .toList();
  }

  group('single-card POS order', () {
    test('sells one card, deducts stock, posts POS debt and delivers twice',
        () async {
      await seedCategory();
      await seedCards(2);
      final inbound = await saveInbound(
        id: 'm-single',
        body: '1 كرت 100 $customerPhone',
      );
      await processInbound(inbound);

      // المخزون: كرت واحد مباع فقط، والثاني بقي متاحًا.
      final rows = (await cards.findByCategory(categoryId)
          as Success<List<Card>>).value;
      expect(rows.where((c) => c.status == CardStatus.sold), hasLength(1));
      expect(rows.where((c) => c.status == CardStatus.available), hasLength(1));

      // قيد مالي واحد على حساب نقطة البيع (دين، ولا يوجد رصيد مسبق).
      final ledger = await posLedger();
      expect(ledger.where((t) => t.type == TransactionType.sale), hasLength(1));
      expect(await posBalanceMinor(), -10000);

      // سجل البيع مربوط بمعرّف العملية المشتق من الرسالة.
      final sale = await sales.findById('message:m-single');
      expect((sale as Success<Sale?>).value, isNotNull);

      // رسالتان: كرت للعميل + تأكيد لنقطة البيع، إلى الرقمين الصحيحين.
      expect(sender.sent, hasLength(2));
      final customerSms =
          sender.sent.singleWhere((s) => s.destination == customerPhone);
      expect(customerSms.body, contains('SN-$categoryId-0'));
      final posSms =
          sender.sent.singleWhere((s) => s.destination == posNotifyPhone);
      expect(posSms.body, contains('نقطة صنعاء'));

      // العقد الدائم قبل الإرسال + تأكيدا التسليم.
      final committed = await messageAudits(inbound.id, 'pos_order_committed');
      expect(committed, hasLength(1));
      expect(committed.single.payloadJson, contains('"quantity":1'));
      expect(
        await messageAudits(inbound.id, 'pos_order_customer_sms_succeeded'),
        hasLength(1),
      );
      expect(
        await messageAudits(inbound.id, 'pos_order_pos_sms_succeeded'),
        hasLength(1),
      );

      final stored =
          (await messages.findById(inbound.id) as Success<IncomingMessage?>)
              .value;
      expect(stored?.status, MessageProcessingStatus.processed);
    });

    test('out of stock is rejected without any financial mutation', () async {
      await seedCategory();
      // لا كروت في الفئة.
      final inbound = await saveInbound(
        id: 'm-empty',
        body: '1 كرت 100 $customerPhone',
      );
      final parsed = await parseInbound(inbound);
      final result = await processor.process(parsed);

      expect((result as Failure<Transaction>).error.code, 'out_of_stock');
      expect(await posLedger(), isEmpty);
      expect(await posBalanceMinor(), 0);
      expect(sender.sent, isEmpty);
      expect(await soldCardCount(), 0);
    });
  });

  group('multi-card POS order (quantity > 1)', () {
    test('commits one independent card, reservation and ledger per card',
        () async {
      await seedCategory();
      await seedCards(5);
      final inbound = await saveInbound(
        id: 'm-batch',
        body: '3 كروت 100 $customerPhone',
      );

      final parsed = await parseInbound(inbound);
      expect(parsed.quantity, 3);
      expect(parsed.posId, posId);

      final result = await processor.process(parsed);
      expect(
        result,
        isA<Success<Transaction>>(),
        reason: 'a fully delivered 3-card POS order must not report failure: '
            '${result is Failure<Transaction> ? result.error.code : ''}',
      );

      // ثلاثة كروت مستقلة مباعة.
      expect(await soldCardCount(), 3);
      final rows = (await cards.findByCategory(categoryId)
          as Success<List<Card>>).value;
      final sold = rows.where((c) => c.status == CardStatus.sold).toList();
      expect(sold.map((c) => c.id).toSet(), hasLength(3));

      // ثلاثة قيود مالية مستقلة، مرجع كل واحد مشتق من فهرسه.
      final ledger = await posLedger();
      final saleRefs = ledger
          .where((t) => t.type == TransactionType.sale)
          .map((t) => t.reference)
          .toList();
      expect(saleRefs, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(saleRefs, contains('sale-op:message:m-batch:$i'));
      }
      expect(await posBalanceMinor(), -30000);

      // ثلاث صفوف بيع مستقلة، كل كرت مرة واحدة.
      final saleRows = (await sales.listRecent(limit: 10) as Success<List<Sale>>)
          .value;
      expect(saleRows.map((s) => s.cardId).toSet(), hasLength(3));

      // رسالتان فقط: واحدة للعميل تحمل الكروت الثلاثة، وواحدة لتأكيد النقطة.
      expect(sender.sent, hasLength(2));
      final customerSms =
          sender.sent.singleWhere((s) => s.destination == customerPhone);
      for (var i = 0; i < 3; i++) {
        expect(customerSms.body, contains('SN-$categoryId-$i'));
      }
      final posSms =
          sender.sent.singleWhere((s) => s.destination == posNotifyPhone);
      expect(posSms.body, contains('3'));

      final committed = await messageAudits(inbound.id, 'pos_order_committed');
      expect(committed, hasLength(1));
      expect(committed.single.payloadJson, contains('"quantity":3'));

      final stored =
          (await messages.findById(inbound.id) as Success<IncomingMessage?>)
              .value;
      expect(stored?.status, MessageProcessingStatus.processed);
    });

    test('insufficient stock releases every reservation and sells nothing',
        () async {
      await seedCategory();
      await seedCards(2);
      final inbound = await saveInbound(
        id: 'm-short',
        body: '3 كروت 100 $customerPhone',
      );
      final parsed = await parseInbound(inbound);
      final result = await processor.process(parsed);

      expect((result as Failure<Transaction>).error.code, 'out_of_stock');
      final rows = (await cards.findByCategory(categoryId)
          as Success<List<Card>>).value;
      expect(rows.where((c) => c.status == CardStatus.available), hasLength(2));
      expect(rows.where((c) => c.status == CardStatus.reserved), isEmpty);
      expect(await soldCardCount(), 0);
      expect(await posLedger(), isEmpty);
      expect(sender.sent, isEmpty);
    });

    test('re-processing the same parsed order allocates nothing extra',
        () async {
      await seedCategory();
      await seedCards(4);
      final inbound = await saveInbound(
        id: 'm-once',
        body: '2 كروت 100 $customerPhone',
      );
      final parsed = await parseInbound(inbound);

      final first = await processor.process(parsed);
      expect(first, isA<Success<Transaction>>());

      final second = await processor.process(parsed);
      // إعادة المعالجة إما تسترد نفس العملية، أو تُرفض صراحة بأنها مُعالجة —
      // وكلاهما لا يُنتج أي أثر تجاري إضافي.
      if (second is Failure<Transaction>) {
        expect(second.error.code, 'message_already_processed');
      } else {
        expect(second, isA<Success<Transaction>>());
      }

      expect(await soldCardCount(), 2);
      expect(await posLedger(), hasLength(2));
      expect(await posBalanceMinor(), -20000);
      expect(
        await messageAudits(inbound.id, 'pos_order_committed'),
        hasLength(1),
      );
      // العميل مرة واحدة، ونقطة البيع مرة واحدة.
      expect(
        sender.sent.where((s) => s.destination == customerPhone),
        hasLength(1),
      );
      expect(sender.sent.where((s) => s.destination == posNotifyPhone),
          hasLength(1));
    });
  });

  group('failure and recovery', () {
    test('the committed order survives an SMS failure and the worker retries',
        () async {
      await seedCategory();
      await seedCards(3);
      final inbound = await saveInbound(
        id: 'm-smsfail',
        body: '1 كرت 100 $customerPhone',
      );

      sender.failures[1] = const AppFailure(
        code: 'sms_send_failed',
        message: 'radio rejected SMS',
      );
      final parsed = await parseInbound(inbound);
      final attempted = await processor.process(parsed);

      // العقد الدائم مكتوب والكرت مباع، لكن التسليم لم يكتمل.
      expect(attempted, isA<Success<Transaction>>());
      expect(await soldCardCount(), 1);
      expect(
        await messageAudits(inbound.id, 'pos_order_committed'),
        hasLength(1),
      );
      expect(
        await messageAudits(inbound.id, 'pos_order_customer_sms_failed'),
        hasLength(1),
      );
      expect(sender.sent, isEmpty);
      final afterFailure =
          (await messages.findById(inbound.id) as Success<IncomingMessage?>)
              .value;
      expect(afterFailure?.status, MessageProcessingStatus.failed);
      final ledgerAfterFailure = await posLedger();
      expect(ledgerAfterFailure, hasLength(1));

      // الدورة الدورية تكمل التسليم بدون تخصيص كرت إضافي.
      sender.failures.clear();
      final report = await worker.tick();
      final value = (report as Success<PosOrderDeliveryWorkerReport>).value;
      expect(value.attempted, 1);
      expect(sender.sent, hasLength(2));
      expect(await soldCardCount(), 1);
      expect(await posLedger(), hasLength(1));

      // دورة ثانية: لا رسالة إضافية (منع التكرار).
      final second = (await worker.tick()
              as Success<PosOrderDeliveryWorkerReport>)
          .value;
      expect(second.attempted, 0);
      expect(sender.sent, hasLength(2));
      final healed =
          (await messages.findById(inbound.id) as Success<IncomingMessage?>)
              .value;
      expect(healed?.status, MessageProcessingStatus.processed);
    });

    test('a failing POS confirmation does not re-send the customer voucher',
        () async {
      await seedCategory();
      await seedCards(2);
      final inbound = await saveInbound(
        id: 'm-posfail',
        body: '1 كرت 100 $customerPhone',
      );

      // النداء الأول (رسالة العميل) ينجح، والثاني (تأكيد النقطة) يفشل.
      sender.failures[2] = const AppFailure(
        code: 'sms_send_failed',
        message: 'radio rejected SMS',
      );
      await processInbound(inbound);
      expect(sender.sent, hasLength(1));
      expect(sender.sent.single.destination, customerPhone);

      sender.failures.clear();
      await worker.tick();

      // رسالة العميل لم تُعد إرسالها، ورسالة التأكيد أُرسلت مرة واحدة.
      expect(
        sender.sent.where((s) => s.destination == customerPhone),
        hasLength(1),
      );
      expect(
        sender.sent.where((s) => s.destination == posNotifyPhone),
        hasLength(1),
      );
      expect(await soldCardCount(), 1);
      expect(await posLedger(), hasLength(1));
    });

    test('worker self-heals an order left failed after full delivery', () async {
      await seedCategory();
      await seedCards(2);
      final inbound = await saveInbound(
        id: 'm-stale',
        body: '1 كرت 100 $customerPhone',
      );
      await processInbound(inbound);

      // حالة عالقة كما لو انقطعت العملية بعد التسليم وقبل تحديث الحالة.
      await messages.updateStatus(inbound.id, MessageProcessingStatus.failed);
      sender.sent.clear();

      final report = (await worker.tick()
              as Success<PosOrderDeliveryWorkerReport>)
          .value;
      expect(report.attempted, 0);
      expect(sender.sent, isEmpty);
      final healed =
          (await messages.findById(inbound.id) as Success<IncomingMessage?>)
              .value;
      expect(healed?.status, MessageProcessingStatus.processed);
      expect(await soldCardCount(), 1);
    });

    test('order for an inactive POS account is refused without mutation',
        () async {
      await seedCategory();
      await seedCards(2);
      final inbound = await saveInbound(
        id: 'm-inactive',
        body: '1 كرت 100 $customerPhone',
      );
      await posRegistry.save(
        PosAccount(
          posId: posId,
          customerId: posLedgerCustomerId,
          name: 'نقطة صنعاء',
          identifiers: const [posPhone],
          notifyPhone: posNotifyPhone,
          status: PointOfSaleStatus.suspended,
        ),
      );

      final parsed = await parseInbound(inbound);
      final result = await processor.process(parsed);
      expect(result, isA<Failure<Transaction>>());
      expect(await soldCardCount(), 0);
      expect(await posLedger(), isEmpty);
      expect(sender.sent, isEmpty);
    });
  });
}

final class _RecordingSender implements MessageSender {
  final List<({String destination, String body})> sent = [];

  /// Failures keyed by 1-based call index.
  final Map<int, AppFailure> failures = {};

  int calls = 0;

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    calls++;
    final failure = failures[calls];
    if (failure != null) return Failure(failure);
    sent.add((destination: destination, body: body));
    return const Success(null);
  }
}
