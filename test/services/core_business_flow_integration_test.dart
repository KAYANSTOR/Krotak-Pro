import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction, IncomingMessage, AuditLog;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/audit.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/local_transfer_processor.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalMessageRepository messages;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalAuditLogRepository auditLogs;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
  late _FakeMessageSender sender;
  late LocalTransferProcessor processor;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    messages = LocalMessageRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 12, 1));
    ids = SequentialIdGenerator();

    customerService = LocalCustomerService(customers: customers, auditLogs: auditLogs, unitOfWork: unitOfWork, clock: clock, ids: ids);
    balanceService = LocalCustomerBalanceService(customers: customers, transactions: transactions, auditLogs: auditLogs, unitOfWork: unitOfWork, clock: clock, ids: ids);
    catalogService = LocalCardCatalogService(categories: categories, cards: cards, auditLogs: auditLogs, unitOfWork: unitOfWork, clock: clock, ids: ids);
    inventoryService = LocalCardInventoryService(categories: categories, cards: cards, unitOfWork: unitOfWork);
    saleService = LocalSaleService(customers: customers, categories: categories, cards: cards, sales: sales, transactions: transactions, balances: balanceService, inventory: inventoryService, auditLogs: auditLogs, unitOfWork: unitOfWork, clock: clock, ids: ids);
    sender = _FakeMessageSender();
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
    );
  });

  tearDown(() async => database.close());

  Future<Customer> seedCustomer() async {
    final result = await customerService.create(displayName: 'Ali', identifierType: CustomerIdentifierType.phoneNumber, identifierValue: '733000000');
    return (result as Success<Customer>).value;
  }

  Future<void> seedCategoryAndCard({required int minorUnits, String categoryId = 'cat-200', String cardId = 'card-1'}) async {
    final category = await catalogService.saveCategory(CardCategory(id: categoryId, name: 'Value $minorUnits', faceValue: Money(minorUnits: minorUnits, currencyCode: 'YER'), isActive: true));
    expect(category, isA<Success<CardCategory>>());
    final imported = await catalogService.importCards(categoryId: categoryId, drafts: [CardImportDraft(serialNumber: 'SN-$cardId', secretCode: 'SECRET-$cardId')]);
    expect(imported, isA<Success<int>>());
  }

  Future<void> seedMessage(String id) async {
    final saved = await messages.save(IncomingMessage(id: id, sender: 'bank', body: 'transfer', receivedAt: clock.now(), status: MessageProcessingStatus.parsed, externalReference: 'bank:REF-$id', customerIdentifier: '733000000'));
    expect(saved, isA<Success<void>>());
  }

  ParsedTransfer transfer(String id, int amount, {String? reference}) => ParsedTransfer(messageId: id, amount: Money(minorUnits: amount, currencyCode: 'YER'), customerIdentifier: '733000000', identifierType: TransferIdentifierType.phone, reference: reference ?? 'REF-$id');

  test('transfer amount 200 selects category 200, sells one card, delivers once, and records ledger/audit', () async {
    final customer = await seedCustomer();
    await seedCategoryAndCard(minorUnits: 200);
    await seedMessage('m1');
    final result = await processor.process(transfer('m1', 200));
    final cardRows = await cards.findByCategory('cat-200');
    final customerLedger = await transactions.findByCustomer(customer.id);
    final sale = await sales.findById('REF-m1');
    final audits = await auditLogs.findByEntity('message', 'm1');
    expect(result, isA<Success<Transaction>>());
    expect(sender.calls, 1);
    expect(sender.lastBody, contains('SN-card-1'));
    expect((cardRows as Success<List<Card>>).value.single.status, CardStatus.sold);
    expect((sale as Success<Sale?>).value?.id, 'REF-m1');
    expect((customerLedger as Success<List<Transaction>>).value.where((item) => item.type == TransactionType.sale), hasLength(1));
    expect((audits as Success<List<AuditLog>>).value.any((item) => item.action == 'sms_delivery_succeeded'), isTrue);
  });

  test('unmatched transfer amount is rejected without credit, reservation, sale, or delivery', () async {
    final customer = await seedCustomer();
    await seedCategoryAndCard(minorUnits: 500, categoryId: 'cat-500');
    await seedMessage('m2');
    final result = await processor.process(transfer('m2', 200));
    final balance = await balanceService.getBalance(customerId: customer.id, currencyCode: 'YER');
    final available = await cards.findAvailableByCategory('cat-500');
    final audits = await auditLogs.findByEntity('message', 'm2');
    expect((result as Failure<Transaction>).error.code, 'unmatched_amount_pending');
    expect((balance as Success<Money>).value.minorUnits, 0);
    expect((available as Success<List<Card>>).value, hasLength(1));
    expect(sender.calls, 0);
    expect((audits as Success<List<AuditLog>>).value.any((item) => item.action == 'transfer_unmatched_amount_pending'), isTrue);
  });

  test('matching category without stock is rejected without financial mutation', () async {
    final customer = await seedCustomer();
    final result = await catalogService.saveCategory(const CardCategory(id: 'cat-200', name: 'Value 200', faceValue: Money(minorUnits: 200, currencyCode: 'YER'), isActive: true));
    expect(result, isA<Success<CardCategory>>());
    await seedMessage('m3');
    final processed = await processor.process(transfer('m3', 200));
    final balance = await balanceService.getBalance(customerId: customer.id, currencyCode: 'YER');
    expect((processed as Failure<Transaction>).error.code, 'out_of_stock');
    expect((balance as Success<Money>).value.minorUnits, 0);
    expect(sender.calls, 0);
  });

  test('retry with same operation id does not create a second sale, ledger, reservation, or SMS', () async {
    final customer = await seedCustomer();
    await seedCategoryAndCard(minorUnits: 200);
    await seedMessage('m4');
    final first = await processor.process(transfer('m4', 200, reference: 'RETRY-200'));
    final second = await processor.process(transfer('m4', 200, reference: 'RETRY-200'));
    final ledger = await transactions.findByReference('sale-op:RETRY-200');
    final sale = await sales.findById('RETRY-200');
    final rows = await transactions.findByCustomer(customer.id);
    expect(first, isA<Success<Transaction>>());
    expect(second, isA<Success<Transaction>>());
    expect((ledger as Success<Transaction?>).value?.reference, 'sale-op:RETRY-200');
    expect((sale as Success<Sale?>).value?.id, 'RETRY-200');
    expect((rows as Success<List<Transaction>>).value.where((item) => item.type == TransactionType.sale), hasLength(1));
    expect(sender.calls, 1);
  });

  test('SMS failure releases reservation and keeps retry financially idempotent', () async {
    final customer = await seedCustomer();
    await seedCategoryAndCard(minorUnits: 200);
    await seedMessage('m5');
    sender.fail = true;
    final first = await processor.process(transfer('m5', 200, reference: 'SMS-FAIL'));
    sender.fail = false;
    final second = await processor.process(transfer('m5', 200, reference: 'SMS-FAIL'));
    final rows = await cards.findByCategory('cat-200');
    final ledger = await transactions.findByReference('sale-op:SMS-FAIL');
    expect((first as Failure<Transaction>).error.code, 'sms_send_failed');
    expect(second, isA<Success<Transaction>>());
    expect((rows as Success<List<Card>>).value.single.status, CardStatus.sold);
    expect((ledger as Success<Transaction?>).value, isNotNull);
    expect(sender.calls, 2);
    expect(customer.id, isNotEmpty);
  });

  test('two concurrent operations can consume the single card at most once', () async {
    await seedCustomer();
    await seedCategoryAndCard(minorUnits: 200);
    await seedMessage('m6');
    final results = await Future.wait([processor.process(transfer('m6', 200, reference: 'CONCURRENT-A')), processor.process(transfer('m6', 200, reference: 'CONCURRENT-B'))]);
    final cardRows = await cards.findByCategory('cat-200');
    final salesRows = await sales.listRecent(limit: 10);
    final successes = results.whereType<Success<Transaction>>().length;
    expect(successes, lessThanOrEqualTo(1));
    expect((cardRows as Success<List<Card>>).value.where((c) => c.status == CardStatus.sold), hasLength(1));
    expect((salesRows as Success<List<Sale>>).value, hasLength(1));
  });

  test('successful sale can be reversed using its stable operation id and original ledger link', () async {
    final customer = await seedCustomer();
    await seedCategoryAndCard(minorUnits: 200);
    await seedMessage('m7');
    final completed = await processor.process(transfer('m7', 200, reference: 'REV-200'));
    final saleTxn = (completed as Success<Transaction>).value;
    final reversed = await saleService.reverseSale(saleId: 'REV-200');
    final cardRows = await cards.findByCategory('cat-200');
    final ledgerRows = await transactions.findByCustomer(customer.id);
    expect(saleTxn.reference, 'sale-op:REV-200');
    expect(reversed, isA<Success<Sale>>());
    expect((cardRows as Success<List<Card>>).value.single.status, CardStatus.available);
    final rows = (ledgerRows as Success<List<Transaction>>).value;
    expect(rows.where((item) => item.type == TransactionType.sale), hasLength(1));
    expect(rows.where((item) => item.type == TransactionType.reversal), hasLength(1));
    expect(rows.singleWhere((item) => item.type == TransactionType.reversal).relatedTransactionId, isNotNull);
  });
}

final class _FakeMessageSender implements MessageSender {
  int calls = 0;
  bool fail = false;
  String? lastBody;

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    calls++;
    lastBody = body;
    if (fail) return const Failure<void>(AppFailure(code: 'sms_send_failed', message: 'SMS send failed'));
    return const Success<void>(null);
  }
}
