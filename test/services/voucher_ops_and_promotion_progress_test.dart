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
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/local_promotion_catalog.dart';
import 'package:net_app/domain/services/local_promotion_progress_service.dart';
import 'package:net_app/domain/services/local_voucher_ops_service.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  late AppDatabase database;
  late LocalCustomerRepository customers;
  late LocalCardCategoryRepository categories;
  late LocalCardRepository cards;
  late LocalTransactionRepository transactions;
  late LocalSaleRepository sales;
  late LocalAuditLogRepository auditLogs;
  late LocalSettingsRepository settings;
  late DriftUnitOfWork unitOfWork;
  late FixedClock clock;
  late SequentialIdGenerator ids;
  late LocalCustomerService customerService;
  late LocalCustomerBalanceService balanceService;
  late LocalCardCatalogService catalogService;
  late LocalCardInventoryService inventoryService;
  late LocalVoucherOpsService voucherOps;
  late LocalPromotionCatalog promotionCatalog;
  late LocalPromotionProgressService promotionProgress;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    customers = LocalCustomerRepository(database);
    categories = LocalCardCategoryRepository(database);
    cards = LocalCardRepository(database);
    transactions = LocalTransactionRepository(database);
    sales = LocalSaleRepository(database);
    auditLogs = LocalAuditLogRepository(database);
    settings = LocalSettingsRepository(database);
    unitOfWork = DriftUnitOfWork(database);
    clock = FixedClock(DateTime(2026, 9, 16, 12));
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
    voucherOps = LocalVoucherOpsService(
      cards: cards,
      sales: sales,
      transactions: transactions,
      balances: balanceService,
      auditLogs: auditLogs,
      unitOfWork: unitOfWork,
      clock: clock,
      ids: ids,
    );
    promotionCatalog = LocalPromotionCatalog(
      settings: settings,
      clock: clock,
      ids: ids,
    );
    promotionProgress = LocalPromotionProgressService(
      promotions: promotionCatalog,
      transactions: transactions,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> createCustomer() async {
    final result = await customerService.create(
      displayName: 'Ali',
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: '733000111',
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

  Future<Card> addAvailableCard() async {
    await createCategory();
    final imported = await catalogService.importCards(
      categoryId: 'cat-500',
      drafts: const [
        CardImportDraft(serialNumber: 'SN-500-1', secretCode: 'SEC-500-1'),
      ],
    );
    expect(imported, isA<Success<int>>());
    final available = await cards.findAvailableByCategory('cat-500');
    return (available as Success<List<Card>>).value.first;
  }

  Future<Card> reserveStock({required String reservationId}) async {
    final reserved = await inventoryService.reserveAvailableCard(
      categoryId: 'cat-500',
      reservationId: reservationId,
      now: clock.now(),
      expiresAt: clock.now().add(const Duration(minutes: 10)),
    );
    return (reserved as Success<Card>).value;
  }

  group('LocalVoucherOpsService', () {
    test('confirmManualDelivery marks reserved card sold and audits', () async {
      await addAvailableCard();
      final reserved = await reserveStock(reservationId: 'res-1');

      final confirmed = await voucherOps.confirmManualDelivery(
        cardId: reserved.id,
        saleId: 'sale-manual-1',
        note: 'handed in shop',
      );
      expect(confirmed, isA<Success<void>>());

      final reloaded = await cards.findById(reserved.id);
      expect((reloaded as Success<Card?>).value?.status, CardStatus.sold);
    });

    test('confirmManualDelivery rejects available card', () async {
      final card = await addAvailableCard();
      final result = await voucherOps.confirmManualDelivery(
        cardId: card.id,
        saleId: 'sale-x',
      );
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).error.code, 'card_not_reserved');
    });

    test('releaseReservationAndRollback returns card to stock and credits customer',
        () async {
      final customer = await createCustomer();
      final card = await addAvailableCard();
      final reserved = await reserveStock(reservationId: 'res-2');

      final released = await voucherOps.releaseReservationAndRollback(
        cardId: reserved.id,
        customerId: customer.id,
        amount: const Money(minorUnits: 500, currencyCode: 'YER'),
        reservationId: 'res-2',
        reason: 'customer_cancelled',
      );
      expect(released, isA<Success<void>>());

      final reloaded = await cards.findById(card.id);
      expect((reloaded as Success<Card?>).value?.status, CardStatus.available);
      expect(card.id, reserved.id);
    });

    test('confirmManualDelivery on missing card fails', () async {
      final result = await voucherOps.confirmManualDelivery(
        cardId: 'missing',
        saleId: 'sale-x',
      );
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).error.code, 'card_not_found');
    });
  });

  group('LocalPromotionProgressService', () {
    test('empty catalog yields empty progress', () async {
      final customer = await createCustomer();
      final result = await promotionProgress.forCustomer(customer.id);
      expect(result, isA<Success<List<PromotionProgress>>>());
      expect((result as Success<List<PromotionProgress>>).value, isEmpty);
    });

    test('accumulates completed sales toward active promotion threshold', () async {
      final customer = await createCustomer();
      await promotionCatalog.create(
        title: 'شراء بـ 1000',
        thresholdMinorUnits: 1000,
        rewardCategoryId: 'cat-500',
      );

      final saleTx = Transaction(
        id: ids.next('tx'),
        customerId: customer.id,
        type: TransactionType.sale,
        amount: const Money(minorUnits: 600, currencyCode: 'YER'),
        reference: 'sale-progress-1',
        status: TransactionStatus.completed,
        createdAt: clock.now(),
      );
      await transactions.append(saleTx);

      final result = await promotionProgress.forCustomer(customer.id);
      expect(result, isA<Success<List<PromotionProgress>>>());
      final items = (result as Success<List<PromotionProgress>>).value;
      expect(items, hasLength(1));
      expect(items.first.accumulatedMinor, 600);
      expect(items.first.qualified, isFalse);
      expect(items.first.remainingMinor, 400);
    });

    test('qualifies when accumulated sales meet threshold', () async {
      final customer = await createCustomer();
      await promotionCatalog.create(
        title: 'عتبة 500',
        thresholdMinorUnits: 500,
        rewardCategoryId: 'cat-500',
      );
      await transactions.append(
        Transaction(
          id: ids.next('tx'),
          customerId: customer.id,
          type: TransactionType.sale,
          amount: const Money(minorUnits: 500, currencyCode: 'YER'),
          reference: 'sale-progress-2',
          status: TransactionStatus.completed,
          createdAt: clock.now(),
        ),
      );

      final items = ((await promotionProgress.forCustomer(customer.id))
              as Success<List<PromotionProgress>>)
          .value;
      expect(items.first.qualified, isTrue);
      expect(items.first.ratio, 1.0);
    });
  });
}
