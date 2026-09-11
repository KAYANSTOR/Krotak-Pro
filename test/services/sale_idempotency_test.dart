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

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 12, 1));
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

  test(
    'retries with the same operation id return one sale and one ledger entry',
    () async {
      final customer =
          (await customerService.create(
            displayName: 'Ali',
            identifierType: CustomerIdentifierType.phoneNumber,
            identifierValue: '733000000',
          ) as Success<Customer>)
              .value;

      await catalogService.saveCategory(
        const CardCategory(
          id: 'cat-500',
          name: 'Yemen Mobile 500',
          faceValue: Money(minorUnits: 500, currencyCode: 'YER'),
          isActive: true,
        ),
      );
      await catalogService.importCards(
        categoryId: 'cat-500',
        drafts: const [
          CardImportDraft(serialNumber: 'A-1', secretCode: 'secret-1'),
          CardImportDraft(serialNumber: 'B-2', secretCode: 'secret-2'),
        ],
      );
      await balanceService.credit(
        customerId: customer.id,
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        reference: 'deposit-1',
      );

      final first = await saleService.sellFromBalance(
        customerId: customer.id,
        categoryId: 'cat-500',
        operationId: 'sale-op-42',
      );
      final second = await saleService.sellFromBalance(
        customerId: customer.id,
        categoryId: 'cat-500',
        operationId: 'sale-op-42',
      );

      final customerLedger = await transactions.findByCustomer(customer.id);
      final allCards = await cards.findByCategory('cat-500');
      final allSales = await sales.findByCustomer(customer.id);

      expect(first, isA<Success<Sale>>());
      expect(second, isA<Success<Sale>>());
      expect((second as Success<Sale>).value.id, 'sale-op-42');
      expect(
        (first as Success<Sale>).value.id,
        (second as Success<Sale>).value.id,
      );
      expect(
        (customerLedger as Success<List<Transaction>>).value
            .where((t) => t.type == TransactionType.sale),
        hasLength(1),
      );
      expect((allSales as Success<List<Sale>>).value, hasLength(1));
      expect(
        (allCards as Success<List<Card>>).value
            .where((c) => c.status.name == 'sold'),
        hasLength(1),
      );
    },
  );
}
