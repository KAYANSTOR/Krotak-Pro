import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart'
    hide Customer, Card, Sale, TransferTemplate, CardCategory, Transaction;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/card.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
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
  late LocalCustomerBalanceService balances;
  late LocalCardCatalogService catalog;
  late LocalCardInventoryService inventory;
  late LocalSaleService service;

  const face = Money(minorUnits: 50000, currencyCode: 'YER');

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 12, 12));
    ids = SequentialIdGenerator();
    balances = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    catalog = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    inventory = LocalCardInventoryService(
      categories: categories,
      cards: cards,
      unitOfWork: unitOfWork,
    );
    service = LocalSaleService(
      customers: customers,
      categories: categories,
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balances,
      inventory: inventory,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() => database.close());

  Future<void> seed({int count = 2}) async {
    final category = await catalog.saveCategory(
      const CardCategory(
        id: 'cat-500',
        name: 'فئة 500',
        faceValue: face,
        isActive: true,
      ),
    );
    expect(category, isA<Success<CardCategory>>());
    final imported = await catalog.importCards(
      categoryId: 'cat-500',
      drafts: [
        for (var i = 1; i <= count; i++)
          CardImportDraft(serialNumber: 'S-$i', secretCode: 'CODE-$i'),
      ],
    );
    expect(imported, isA<Success<int>>());
  }

  test('cash sale creates customer, deposit and sale with zero balance', () async {
    await seed();
    final result = await service.sellManual(
      phone: '733111222',
      displayName: 'أحمد',
      amount: face,
      method: ManualSaleMethod.cash,
      operationId: 'op-cash-1',
    );
    expect(result, isA<Success<Sale>>());
    final customerResult = await customers.findByIdentifier('733111222');
    final customer = (customerResult as Success<Customer?>).value!;
    final balance = await balances.getBalance(customerId: customer.id, currencyCode: 'YER');
    expect((balance as Success<Money>).value.minorUnits, 0);
    final txns = await transactions.findByCustomer(customer.id);
    final list = (txns as Success<List<Transaction>>).value;
    expect(list.where((t) => t.type == TransactionType.deposit).length, 1);
    expect(list.where((t) => t.type == TransactionType.sale).length, 1);
  });

  test('credit sale creates debt without deposit', () async {
    await seed();
    final result = await service.sellManual(
      phone: '733333444',
      displayName: 'سارة',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-credit-1',
    );
    expect(result, isA<Success<Sale>>());
    final customer = (await customers.findByIdentifier('733333444') as Success<Customer?>).value!;
    final balance = await balances.getBalance(customerId: customer.id, currencyCode: 'YER');
    expect((balance as Success<Money>).value.minorUnits, -face.minorUnits);
    final txns = await transactions.findByCustomer(customer.id);
    final list = (txns as Success<List<Transaction>>).value;
    expect(list.where((t) => t.type == TransactionType.deposit).length, 0);
    expect(list.where((t) => t.type == TransactionType.sale).length, 1);
  });

  test('same operationId is idempotent', () async {
    await seed();
    final first = await service.sellManual(
      phone: '733777888',
      displayName: 'تكرار',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-idem',
    );
    final second = await service.sellManual(
      phone: '733777888',
      displayName: 'تكرار',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-idem',
    );
    expect(first, isA<Success<Sale>>());
    expect(second, isA<Success<Sale>>());
    expect((first as Success<Sale>).value.id, (second as Success<Sale>).value.id);
  });

  test('unmatched amount is rejected', () async {
    await seed();
    final result = await service.sellManual(
      phone: '733999000',
      displayName: 'بدون فئة',
      amount: const Money(minorUnits: 99900, currencyCode: 'YER'),
      method: ManualSaleMethod.cash,
    );
    expect(result, isA<Failure<Sale>>());
    expect((result as Failure<Sale>).error.code, 'category_not_found_for_amount');
  });
}
