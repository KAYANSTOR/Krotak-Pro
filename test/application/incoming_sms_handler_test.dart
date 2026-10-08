import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
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
        TransferTemplate;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_message_parser.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';
import 'package:net_app/platform/sms_bridge.dart';

import '../helpers/trusted_payment_source.dart';

/// أحد أهم مسارات Krotak: SMS الواردة، والرسائل المخزّنة أثناء إغلاق التطبيق،
/// ومنع تكرار العملية عند وصول نفس الرسالة أكثر من مرة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* ------------------------------------------------------------------ */
  /* 1. الجسر الأصلي: عقد القنوات (قراءة قائمة الانتظار + الإقرار)        */
  /* ------------------------------------------------------------------ */

  group('SmsBridge platform contract', () {
    final binding = TestWidgetsFlutterBinding.instance;
    const channel = MethodChannel('com.kayan.net/sms');

    List<String> acked = [];
    List<dynamic>? pendingPayload;

    setUp(() {
      acked = [];
      pendingPayload = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'peekPendingSms':
            return pendingPayload;
          case 'ackPendingSms':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            acked.addAll(
              (args['ids'] as List).map((e) => e.toString()),
            );
            return null;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('peekPendingSms decodes sender, body, timestamp and pending id',
        () async {
      pendingPayload = <dynamic>[
        <String, dynamic>{
          'id': 'pending-1',
          'sender': 'bank',
          'body': 'transfer 200 to 733000000 ref R1',
          'timestampMillis': 1758600000000,
        },
      ];

      final pending = await SmsBridge().peekPendingSms();

      expect(pending, hasLength(1));
      final event = pending.single;
      expect(event.pendingId, 'pending-1');
      expect(event.sender, 'bank');
      expect(event.body, 'transfer 200 to 733000000 ref R1');
      expect(event.timestampMillis, 1758600000000);
      expect(
        event.receivedAt,
        DateTime.fromMillisecondsSinceEpoch(1758600000000, isUtc: true),
      );
    });

    test('peekPendingSms maps a null platform reply to an empty batch', () async {
      expect(await SmsBridge().peekPendingSms(), isEmpty);
    });

    test('ackPendingSms is a no-op for an empty batch', () async {
      await SmsBridge().ackPendingSms(const []);
      expect(acked, isEmpty);
    });

    test('ackPendingSms sends the exact ids back to the native store', () async {
      await SmsBridge().ackPendingSms(const ['pending-1', 'pending-2']);
      expect(acked, ['pending-1', 'pending-2']);
    });
  });

  /* ------------------------------------------------------------------ */
  /* 2. IncomingSmsHandler: قائمة الانتظار، التكرار، والإقرار             */
  /* ------------------------------------------------------------------ */

  group('IncomingSmsHandler ingress', () {
    late AppDatabase database;
    late LocalCustomerRepository customers;
    late LocalCardCategoryRepository categories;
    late LocalCardRepository cards;
    late LocalMessageRepository messages;
    late LocalTransactionRepository transactions;
    late LocalSaleRepository sales;
    late LocalAuditLogRepository audits;
    late DriftUnitOfWork uow;
    late FixedClock clock;
    late SequentialIdGenerator ids;
    late LocalCustomerService customerService;
    late LocalSettingsRepository settings;
    late LocalCustomerBalanceService balanceService;
    late LocalCardCatalogService catalogService;
    late LocalCardInventoryService inventoryService;
    late LocalSaleService saleService;
    late _RecordingSender sender;
    late LocalTransferProcessor processor;

    const trustedBody = 'transfer 200 to 733000000 ref R-INGRESS';
    const senderPhone = '733000000';

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      settings = LocalSettingsRepository(database);
      customers = LocalCustomerRepository(database);
      categories = LocalCardCategoryRepository(database);
      cards = LocalCardRepository(database);
      messages = LocalMessageRepository(database);
      transactions = LocalTransactionRepository(database);
      sales = LocalSaleRepository(database);
      audits = LocalAuditLogRepository(database);
      uow = DriftUnitOfWork(database);
      clock = FixedClock(DateTime(2026, 9, 24, 9));
      ids = SequentialIdGenerator();

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
      );

      await customerService.create(
        displayName: 'عميل الوارد',
        identifierType: CustomerIdentifierType.phoneNumber,
        identifierValue: senderPhone,
      );
      await catalogService.saveCategory(
        const CardCategory(
          id: 'cat-ingress',
          name: 'فئة 200',
          faceValue: Money(minorUnits: 20000, currencyCode: 'YER'),
          isActive: true,
        ),
      );
      await catalogService.importCards(
        categoryId: 'cat-ingress',
        drafts: const [
          CardImportDraft(serialNumber: 'SN-IN-1', secretCode: 'PIN-IN-1'),
          CardImportDraft(serialNumber: 'SN-IN-2', secretCode: 'PIN-IN-2'),
          CardImportDraft(serialNumber: 'SN-IN-3', secretCode: 'PIN-IN-3'),
        ],
      );
      // قوالب الرسائل الصادرة تُزرع في الإعدادات كما يفعل التطبيق عند الإقلاع:
      // لا إرسال بلا قالب موجود في الإعدادات.
      await DefaultOutboundTemplatesSeeder(
        settings: settings,
        clock: clock,
      ).seedIfNeeded();
    });

    tearDown(() async => database.close());

    LocalMessageParser buildParser() => LocalMessageParser(
          templates: const [
            TransferTemplate(
              id: 'template-bank',
              name: 'Bank transfer',
              pattern: 'transfer {amount} to {phone} ref {ref}',
              isActive: true,
              walletId: 'wallet-bank',
            ),
          ],
        );

    IncomingSmsHandler buildHandler({
      required SmsBridge bridge,
      TransferProcessor? override,
    }) {
      return IncomingSmsHandler(
        bridge: bridge,
        messages: messages,
        parser: buildParser(),
        processor: override ?? processor,
        ids: ids,
        sourceGuard: trustedPaymentSourceGuard(),
        settings: settings,
      );
    }

    Future<int> messageCount() async {
      final rows = await messages.listRecent(limit: 50);
      return (rows as Success<List<IncomingMessage>>).value.length;
    }

    Future<int> soldCards() async {
      final rows = await cards.findByCategory('cat-ingress');
      return (rows as Success<List<Card>>)
          .value
          .where((c) => c.status == CardStatus.sold)
          .length;
    }

    IncomingSmsEvent event({
      String pendingId = 'pending-1',
      String body = trustedBody,
      int millis = 1758600000000,
    }) {
      return IncomingSmsEvent(
        sender: 'bank',
        body: body,
        timestampMillis: millis,
        pendingId: pendingId,
      );
    }

    test('SMS captured while the app was closed is drained once and acked',
        () async {
      final bridge = _FakeSmsBridge(pending: [event()]);
      final handler = buildHandler(bridge: bridge);

      handler.start();
      await pumpEventQueue();
      handler.stop();

      expect(await messageCount(), 1);
      expect(await soldCards(), 1);
      expect(sender.sent, hasLength(1));
      expect(bridge.ackedIds, ['pending-1']);
    });

    test('an event that carries no pending id is processed but never acked',
        () async {
      final bridge = _FakeSmsBridge(
        pending: [
          const IncomingSmsEvent(
            sender: 'bank',
            body: trustedBody,
            timestampMillis: 1758600000000,
          ),
        ],
      );
      final handler = buildHandler(bridge: bridge);

      handler.start();
      await pumpEventQueue();
      handler.stop();

      expect(await messageCount(), 1);
      expect(bridge.ackBatches.every((batch) => batch.isEmpty), isTrue);
    });

    test('the same SMS arriving twice creates exactly one commercial event',
        () async {
      final bridge = _FakeSmsBridge(
        pending: [
          event(pendingId: 'pending-1'),
          event(pendingId: 'pending-2'),
        ],
      );
      final handler = buildHandler(bridge: bridge);

      handler.start();
      await pumpEventQueue();
      handler.stop();

      expect(await messageCount(), 1);
      expect(await soldCards(), 1);
      expect(sender.sent, hasLength(1));
      final ledger = await transactions.findByReference('sale-op:R-INGRESS');
      expect((ledger as Success<Transaction?>).value, isNotNull);
      // Both native copies are acknowledged; neither replays later.
      expect(bridge.ackedIds, ['pending-1', 'pending-2']);
    });

    test('replaying the same pending batch after a restart stays idempotent',
        () async {
      final first = _FakeSmsBridge(pending: [event()]);
      buildHandler(bridge: first)
        ..start()
        ..stop();
      await pumpEventQueue();

      // التطبيق أُغلق قبل الإقرار ثم أُعيد تشغيله بنفس الرسالة المعلّقة.
      final second = _FakeSmsBridge(pending: [event()]);
      buildHandler(bridge: second)
        ..start()
        ..stop();
      await pumpEventQueue();

      expect(await messageCount(), 1);
      expect(await soldCards(), 1);
      expect(sender.sent, hasLength(1));
      expect(second.ackedIds, ['pending-1']);
    });

    test('a failure while processing leaves the batch unacked so nothing is lost',
        () async {
      final throwing = _ThrowingProcessor();
      final bridge = _FakeSmsBridge(
        pending: [
          event(pendingId: 'pending-1'),
          event(pendingId: 'pending-2', body: '$trustedBody 2'),
        ],
      );
      final handler = buildHandler(bridge: bridge, override: throwing);

      handler.start();
      await pumpEventQueue();
      handler.stop();

      expect(throwing.calls, greaterThan(0));
      expect(
        bridge.ackBatches,
        isEmpty,
        reason: 'an unacknowledged event must stay in the native inbox',
      );
    });

    test('a live SMS is processed while listening and ignored after stop',
        () async {
      final bridge = _FakeSmsBridge(pending: const []);
      final handler = buildHandler(bridge: bridge);

      handler.start();
      await pumpEventQueue();

      bridge.push(event(pendingId: 'live-1'));
      await pumpEventQueue();
      expect(await soldCards(), 1);

      handler.stop();
      bridge.push(
        event(pendingId: 'live-2', body: '$trustedBody 3'),
      );
      await pumpEventQueue();

      expect(
        await soldCards(),
        1,
        reason: 'stopped handler must not keep consuming the stream',
      );
      expect(await messageCount(), 1);
    });

    test('manual ingress deduplicates the very same SMS body', () async {
      final handler = buildHandler(bridge: _FakeSmsBridge(pending: const []));

      final first = await handler.handleManual(
        sender: 'bank',
        body: trustedBody,
        receivedAt: clock.now(),
      );
      final second = await handler.handleManual(
        sender: 'bank',
        body: trustedBody,
        receivedAt: clock.now(),
      );

      expect(first, isA<Success<Transaction?>>());
      expect(second, isA<Success<Transaction?>>());
      expect(await messageCount(), 1);
      expect(await soldCards(), 1);
      expect(sender.sent, hasLength(1));
    });
  });
}

final class _FakeSmsBridge extends SmsBridge {
  _FakeSmsBridge({this.pending = const []});

  final List<IncomingSmsEvent> pending;
  final List<List<String>> ackBatches = [];
  final StreamController<IncomingSmsEvent> _live =
      StreamController<IncomingSmsEvent>.broadcast();

  List<String> get ackedIds =>
      [for (final batch in ackBatches) ...batch];

  void push(IncomingSmsEvent event) => _live.add(event);

  @override
  Stream<IncomingSmsEvent> get incomingSms => _live.stream;

  @override
  Future<List<IncomingSmsEvent>> peekPendingSms() async =>
      List<IncomingSmsEvent>.from(pending);

  @override
  Future<void> ackPendingSms(List<String> ids) async {
    ackBatches.add(List<String>.from(ids));
  }
}

/// Stands in for a processor that dies mid-work (bridge/DB failure) so the
/// handler's durability behaviour can be asserted.
final class _ThrowingProcessor implements TransferProcessor {
  int calls = 0;

  @override
  Future<Result<Transaction>> process(ParsedTransfer transfer) async {
    calls++;
    throw StateError('native bridge died mid-processing');
  }
}

final class _RecordingSender implements MessageSender {
  final List<({String destination, String body})> sent = [];

  @override
  Future<Result<void>> send({
    required String destination,
    required String body,
  }) async {
    sent.add((destination: destination, body: body));
    return const Success(null);
  }
}
