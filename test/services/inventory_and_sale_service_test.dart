import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_sale_service.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
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

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 1, 1, 12));
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
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> createCustomer() async {
    final result = await customerService.create(
      displayName: 'Ali',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000000',
    );
    return (result as Success<Customer>).value;
  }

  Future<CardCategory> createCategory() async {
    final result = await catalogService.saveCategory(
      const CardCategory(
        id: 'cat-500',
        name: 'Yemen Mobile 500',
        faceValue: Money(minorUnits: 500, currencyCode: 'YER'),
        isActive: true,
      ),
    );
    return (result as Success<CardCategory>).value;
  }

  test('creates a customer and rejects a duplicate identifier', () async {
    final created = await customerService.create(
      displayName: 'Ali',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000000',
    );
    final duplicate = await customerService.create(
      displayName: 'Ali Two',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000000',
    );

    expect(created, isA<Success<Customer>>());
    expect((duplicate as Failure<Customer>).error.code, 'duplicate_identifier');
  });

  test('credits a customer idempotently by reference', () async {
    final customer = await createCustomer();
    const amount = Money(minorUnits: 1500, currencyCode: 'YER');

    final first = await balanceService.credit(
      customerId: customer.id,
      amount: amount,
      reference: 'sms-1',
    );
    final second = await balanceService.credit(
      customerId: customer.id,
      amount: amount,
      reference: 'sms-1',
    );
    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );

    expect((first as Success<Transaction>).value.id, (second as Success<Transaction>).value.id);
    expect((balance as Success<Money>).value.minorUnits, 1500);
  });

  test('imports cards and reserves the lowest serial first', () async {
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'B-2', secretCode: 'secret-2'),
        CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
      ],
    );

    final reserved = await inventoryService.reserveAvailableCard(
      categoryId: 'cat-500',
      reservationId: 'res-1',
      now: clock.now(),
      expiresAt: clock.now().add(const Duration(minutes: 5)),
    );

    expect((reserved as Success<Card>).value.serialNumber, 'A-1');
    expect(reserved.value.status, CardStatus.reserved);
  });

  test('sells from balance, deducts the face value, and marks the card sold', () async {
    final customer = await createCustomer();
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
      ],
    );
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
      reference: 'deposit-1',
    );

    final sold = await saleService.sellFromBalance(
      customerId: customer.id,
      categoryId: 'cat-500',
    );
    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    final card = await cards.findById((sold as Success<Sale>).value.cardId);

    expect(sold.value.status, TransactionStatus.completed);
    expect((balance as Success<Money>).value.minorUnits, 500);
    expect((card as Success<Card?>).value?.status, CardStatus.sold);
  });

  test('does not consume a card when the customer balance is insufficient', () async {
    final customer = await createCustomer();
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
      ],
    );

    final sold = await saleService.sellFromBalance(
      customerId: customer.id,
      categoryId: 'cat-500',
    );
    final available = await cards.findAvailableByCategory('cat-500');

    expect((sold as Failure<Sale>).error.code, 'insufficient_balance');
    expect((available as Success<List<Card>>).value, hasLength(1));
  });

  test('reverses a sale, restores the card, and returns the balance', () async {
    final customer = await createCustomer();
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
      ],
    );
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 500, currencyCode: 'YER'),
    );

    final sold = await saleService.sellFromBalance(
      customerId: customer.id,
      categoryId: 'cat-500',
    );
    final reversed = await saleService.reverseSale(
      saleId: (sold as Success<Sale>).value.id,
    );
    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    final card = await cards.findById(sold.value.cardId);

    expect((reversed as Success<Sale>).value.status, TransactionStatus.reversed);
    expect((balance as Success<Money>).value.minorUnits, 500);
    expect((card as Success<Card?>).value?.status, CardStatus.available);
  });

  test('blacklisted customers cannot buy', () async {
    final customer = await createCustomer();
    await createCategory();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
      ],
    );
    await balanceService.credit(
      customerId: customer.id,
      amount: const Money(minorUnits: 500, currencyCode: 'YER'),
    );
    await customerService.blacklist(customer.id);

    final sold = await saleService.sellFromBalance(
      customerId: customer.id,
      categoryId: 'cat-500',
    );

    expect((sold as Failure<Sale>).error.code, 'customer_not_sellable');
  });
}
