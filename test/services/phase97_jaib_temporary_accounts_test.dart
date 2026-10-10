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
        AuditLog;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
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

/// Phase 97 integration tests: Jaib blocked and alternate templates
/// create provisional accounts that stay provisional and receive balance only.
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
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalSaleService saleService;
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
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 10, 10, 12));
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
    sender = _RecordingMessageSender();
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
      customerService: customerService,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedMatchingCategory() async {
    final category = await catalogService.saveCategory(
      CardCategory(
        id: 'cat-100',
        name: '100',
        faceValue: Money(minorUnits: 10000, currencyCode: currency),
        isActive: true,
      ),
    );
    expect(category, isA<Success<CardCategory>>());
    final imported = await catalogService.importCards(
      categoryId: 'cat-100',
      drafts: [
        CardImportDraft(
          serialNumber: 'SN-100',
          secretCode: 'SECRET-100',
        ),
      ],
    );
    expect(imported, isA<Success<int>>());
  }

  test('blocked Jaib template creates provisional account and credits without selling a card', () async {
    await seedMatchingCategory();

    final message = IncomingMessage(
      id: 'msg-blocked',
      sender: 'Jaib',
      body: 'اضيف 100ر.ي تحويل مشترك رص:4650ر.ي من د****-6557728',
      receivedAt: clock.now(),
      status: MessageProcessingStatus.parsed,
    );
    await messages.save(message);

    final transfer = ParsedTransfer(
      messageId: message.id,
      amount: Money(minorUnits: 10000, currencyCode: currency),
      customerIdentifier: '6557728',
      identifierType: TransferIdentifierType.phone,
      reference: 'REF-blocked',
      templateId: 'tpl-default-jaib-ar-blocked',
    );

    final result = await processor.process(transfer);
    expect(result, isA<Success<Transaction>>());

    final customerResult = await customers.findByIdentifier('6557728');
    final customer = (customerResult as Success<Customer?>).value;
    expect(customer, isNotNull);
    expect(customer!.status, CustomerStatus.provisional);

    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: currency,
    );
    expect((balance as Success<Money>).value.minorUnits, 10000);

    final salesResult = await sales.findByCustomer(customer.id);
    expect((salesResult as Success<List<Sale>>).value, isEmpty);

    final available = await cards.findAvailableByCategory('cat-100');
    expect((available as Success<List<Card>>).value, hasLength(1));

    expect(sender.sent, isEmpty);
  });

  test('alternate number template stays provisional across reprocessing', () async {
    final message = IncomingMessage(
      id: 'msg-alt',
      sender: 'Jaib',
      body: 'اضيف 100ر.ي تحويل مشترك رص:1022ر.ي من 687471',
      receivedAt: clock.now(),
      status: MessageProcessingStatus.parsed,
    );
    await messages.save(message);

    final transfer = ParsedTransfer(
      messageId: message.id,
      amount: Money(minorUnits: 10000, currencyCode: currency),
      customerIdentifier: '687471',
      identifierType: TransferIdentifierType.phone,
      reference: 'REF-alt',
      templateId: 'tpl-default-jaib-ar-phone-only',
    );

    expect(await processor.process(transfer), isA<Success<Transaction>>());

    final customer = ((await customers.findByIdentifier('687471')) as Success<Customer?>).value!;
    expect(customer.status, CustomerStatus.provisional);

    expect(await processor.process(transfer), isA<Success<Transaction>>());
    final after = ((await customers.findById(customer.id)) as Success<Customer?>).value!;
    expect(after.status, CustomerStatus.provisional);
  });

  test('ordinary Jaib template still creates an active customer', () async {
    final message = IncomingMessage(
      id: 'msg-normal',
      sender: 'Jaib',
      body: 'اضيف 100ر.ي تحويل مشترك رص:515920ر.ي من علي 715813555',
      receivedAt: clock.now(),
      status: MessageProcessingStatus.parsed,
    );
    await messages.save(message);

    final transfer = ParsedTransfer(
      messageId: message.id,
      amount: Money(minorUnits: 10000, currencyCode: currency),
      customerIdentifier: '715813555',
      identifierType: TransferIdentifierType.phone,
      reference: 'REF-normal',
      templateId: 'tpl-default-jaib-ar-shared',
    );

    await processor.process(transfer);
    final customer = ((await customers.findByIdentifier('715813555')) as Success<Customer?>).value!;
    expect(customer.status, CustomerStatus.active);
  });
}

class _RecordingMessageSender implements MessageSender {
  final sent = <String>[];

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    sent.add('$destination:$body');
    return const Success(null);
  }
}
