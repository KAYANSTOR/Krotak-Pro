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

  const face = Money(minorUnits: 50000, currencyCode: 'YER'); // 500 ر.ي

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

  Future<void> seedCategoryWithCards({int count = 2}) async {
    final cat = await catalogService.saveCategory(
      const CardCategory(
        id: 'cat-500',
        name: 'فئة 500',
        faceValue: face,
        isActive: true,
      ),
    );
    expect(cat, isA<Success<CardCategory>>());
    final drafts = [
      for (var i = 0; i < count; i++)
        CardImportDraft(
          serialNumber: 'S-${i + 1}',
          secretCode: 'CODE-${i + 1}',
        ),
    ];
    final imported = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: drafts,
    );
    expect(imported, isA<Success<int>>());
  }

  test('cash manual sale creates customer, deposit+sale, net balance zero',
      () async {
    await seedCategoryWithCards();

    final sold = await saleService.sellManual(
      phone: '733111222',
      displayName: 'أحمد',
      amount: face,
      method: ManualSaleMethod.cash,
      operationId: 'op-cash-1',
    );
    expect(sold, isA<Success<Sale>>());
    final sale = (sold as Success<Sale>).value;
    expect(sale.amount, face);
    expect(sale.status, TransactionStatus.completed);

    final found = await customers.findByIdentifier('733111222');
    expect(found, isA<Success<Customer?>>());
    final customer = (found as Success<Customer?>).value!;
    expect(customer.displayName, 'أحمد');

    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    expect(balance, isA<Success<Money>>());
    expect((balance as Success<Money>).value.minorUnits, 0);

    final txns = await transactions.findByCustomer(customer.id);
    final list = (txns as Success<List<Transaction>>).value;
    expect(list.where((t) => t.type == TransactionType.deposit).length, 1);
    expect(list.where((t) => t.type == TransactionType.sale).length, 1);
  });

  test('credit manual sale creates debt without deposit', () async {
    await seedCategoryWithCards();

    final sold = await saleService.sellManual(
      phone: '733333444',
      displayName: 'سارة',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-credit-1',
    );
    expect(sold, isA<Success<Sale>>());

    final found = await customers.findByIdentifier('733333444');
    final customer = (found as Success<Customer?>).value!;
    final balance = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    expect((balance as Success<Money>).value.minorUnits, -face.minorUnits);

    final txns = await transactions.findByCustomer(customer.id);
    final list = (txns as Success<List<Transaction>>).value;
    expect(list.where((t) => t.type == TransactionType.deposit).length, 0);
    expect(list.where((t) => t.type == TransactionType.sale).length, 1);
  });

  test('cash manual sale works when customer already has debt', () async {
    await seedCategoryWithCards(count: 3);
    await saleService.sellManual(
      phone: '733555666',
      displayName: 'مدين',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-prior-debt',
    );
    final found = await customers.findByIdentifier('733555666');
    final customer = (found as Success<Customer?>).value!;
    final before = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    expect((before as Success<Money>).value.minorUnits, -face.minorUnits);

    final sold = await saleService.sellManual(
      phone: '733555666',
      displayName: 'مدين',
      amount: face,
      method: ManualSaleMethod.cash,
      operationId: 'op-cash-on-debt',
    );
    expect(sold, isA<Success<Sale>>());
    final after = await balanceService.getBalance(
      customerId: customer.id,
      currencyCode: 'YER',
    );
    expect((after as Success<Money>).value.minorUnits, -face.minorUnits);
  });

  test('idempotent sellManual returns same sale for same operationId',
      () async {
    await seedCategoryWithCards();
    final first = await saleService.sellManual(
      phone: '733777888',
      displayName: 'تكرار',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-idem',
    );
    final second = await saleService.sellManual(
      phone: '733777888',
      displayName: 'تكرار',
      amount: face,
      method: ManualSaleMethod.credit,
      operationId: 'op-idem',
    );
    expect(first, isA<Success<Sale>>());
    expect(second, isA<Success<Sale>>());
    expect(
      (first as Success<Sale>).value.id,
      (second as Success<Sale>).value.id,
    );
  });

  test('rejects when no category matches amount', () async {
    await seedCategoryWithCards();
    final sold = await saleService.sellManual(
      phone: '733999000',
      displayName: 'بدون فئة',
      amount: const Money(minorUnits: 99900, currencyCode: 'YER'),
      method: ManualSaleMethod.cash,
    );
    expect(sold, isA<Failure<Sale>>());
    expect(
      (sold as Failure<Sale>).error.code,
      'category_not_found_for_amount',
    );
  });

  test('rejects empty phone and non-positive amount', () async {
    final noPhone = await saleService.sellManual(
      phone: '  ',
      displayName: 'x',
      amount: face,
      method: ManualSaleMethod.cash,
    );
    expect((noPhone as Failure<Sale>).error.code, 'invalid_phone');

    final badAmount = await saleService.sellManual(
      phone: '733000111',
      displayName: 'x',
      amount: const Money(minorUnits: 0, currencyCode: 'YER'),
      method: ManualSaleMethod.cash,
    );
    expect((badAmount as Failure<Sale>).error.code, 'invalid_amount');
  });
}
