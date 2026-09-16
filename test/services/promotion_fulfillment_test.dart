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
import 'package:net_app/domain/entities/promotion.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/services/local_card_inventory_service.dart';
import 'package:net_app/domain/services/local_catalog_services.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_promotion_catalog.dart';
import 'package:net_app/domain/services/local_promotion_fulfillment_service.dart';
import 'package:net_app/domain/services/local_promotion_progress_service.dart';

void main() {
  late AppDatabase database;
  late LocalPromotionFulfillmentService fulfillment;
  late LocalPromotionCatalog catalog;
  late LocalCustomerService customerService;
  late LocalCardCatalogService catalogService;
  late LocalCardRepository cards;
  late LocalTransactionRepository transactions;
  late FixedClock clock;
  late SequentialIdGenerator ids;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final customers = LocalCustomerRepository(database);
    final categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    final sales = LocalSaleRepository(database);
    final auditLogs = LocalAuditLogRepository(database);
    final settings = LocalSettingsRepository(database);
    final uow = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 16, 12));
    ids = SequentialIdGenerator();
    customerService = LocalCustomerService(
      customers: customers,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    catalogService = LocalCardCatalogService(
      categories: categories,
      cards: cards,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
    catalog = LocalPromotionCatalog(settings: settings, clock: clock, ids: ids);
    final progress = LocalPromotionProgressService(
      promotions: catalog,
      transactions: transactions,
    );
    fulfillment = LocalPromotionFulfillmentService(
      progress: progress,
      promotions: catalog,
      categories: categories,
      cards: cards,
      inventory: LocalCardInventoryService(
        categories: categories,
        cards: cards,
        unitOfWork: uow,
      ),
      sales: sales,
      transactions: transactions,
      auditLogs: auditLogs,
      unitOfWork: uow,
      clock: clock,
      ids: ids,
    );
  });

  tearDown(() async => database.close());

  Future<Customer> customer() async {
    final result = await customerService.create(
      displayName: 'Ali',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000111',
    );
    return (result as Success<Customer>).value;
  }

  Future<void> category() async {
    await catalogService.saveCategory(
      const CardCategory(
        id: 'cat-500',
        name: 'Yemen Mobile 500',
        faceValue: Money(minorUnits: 500, currencyCode: 'YER'),
        isActive: true,
      ),
    );
  }

  test('skips customer below threshold', () async {
    final c = await customer();
    await catalog.create(
      title: 't',
      thresholdMinorUnits: 1000,
      rewardCategoryId: 'cat-500',
    );
    await transactions.append(
      Transaction(
        id: ids.next('tx'),
        customerId: c.id,
        type: TransactionType.sale,
        amount: const Money(minorUnits: 400, currencyCode: 'YER'),
        reference: 'sale-under',
        status: TransactionStatus.completed,
        createdAt: clock.now(),
      ),
    );
    final result = await fulfillment.fulfillQualified(customerId: c.id);
    expect((result as Success<List<Sale>>).value, isEmpty);
  });

  test('awards once then is idempotent', () async {
    final c = await customer();
    await category();
    await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'SN-1', secretCode: 'SEC-1'),
      ],
    );
    await catalog.create(
      title: 't',
      thresholdMinorUnits: 500,
      rewardCategoryId: 'cat-500',
    );
    await transactions.append(
      Transaction(
        id: ids.next('tx'),
        customerId: c.id,
        type: TransactionType.sale,
        amount: const Money(minorUnits: 500, currencyCode: 'YER'),
        reference: 'sale-q',
        status: TransactionStatus.completed,
        createdAt: clock.now(),
      ),
    );
    final first = await fulfillment.fulfillQualified(customerId: c.id);
    final awarded = (first as Success<List<Sale>>).value;
    expect(awarded, hasLength(1));
    final card = await cards.findById(awarded.first.cardId);
    expect((card as Success<Card?>).value?.status, CardStatus.sold);
    final promoId = ((await catalog.listAll()) as Success<List<Promotion>>).value.first.id;
    final ledger = await transactions.findByReference(
      LocalPromotionFulfillmentService.rewardReference(
        promotionId: promoId,
        customerId: c.id,
        cycle: 1,
      ),
    );
    expect((ledger as Success<Transaction?>).value?.type, TransactionType.reward);
    final second = await fulfillment.fulfillQualified(customerId: c.id);
    expect((second as Success<List<Sale>>).value, isEmpty);
  });

  test('fails without reward stock', () async {
    final c = await customer();
    await category();
    await catalog.create(
      title: 't',
      thresholdMinorUnits: 500,
      rewardCategoryId: 'cat-500',
    );
    await transactions.append(
      Transaction(
        id: ids.next('tx'),
        customerId: c.id,
        type: TransactionType.sale,
        amount: const Money(minorUnits: 500, currencyCode: 'YER'),
        reference: 'sale-empty',
        status: TransactionStatus.completed,
        createdAt: clock.now(),
      ),
    );
    final result = await fulfillment.fulfillQualified(customerId: c.id);
    expect((result as Failure<List<Sale>>).error.code, 'reward_stock_unavailable');
  });
}
