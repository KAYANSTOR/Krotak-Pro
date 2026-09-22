import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'manual_sale_runner.dart';
import '../repositories/repositories.dart';
import 'services.dart';

final class LocalSaleService implements SaleService, ReservedSaleService {
  const LocalSaleService({
    required this.customers,
    required this.categories,
    required this.cards,
    required this.sales,
    required this.transactions,
    required this.balances,
    required this.inventory,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
    this.messageSender,
    this.settings,
    this.reservationTtl = const Duration(minutes: 5),
  });

  final CustomerRepository customers;
  final CardCategoryRepository categories;
  final CardRepository cards;
  final SaleRepository sales;
  final TransactionRepository transactions;
  final CustomerBalanceService balances;
  final CardInventoryService inventory;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;
  final MessageSender? messageSender;
  final SettingsRepository? settings;
  final Duration reservationTtl;

  @override
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
    String? operationId,
  }) {
    final stableOperationId = operationId?.trim();
    if (stableOperationId != null && stableOperationId.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_operation_id',
            message: 'Sale operation id must not be empty',
          ),
        ),
      );
    }

    return unitOfWork.run(() async {
      if (stableOperationId != null) {
        final existingSale = await sales.findById(stableOperationId);
        if (existingSale is Failure<Sale?>) return Failure(existingSale.error);
        final existing = (existingSale as Success<Sale?>).value;
        if (existing != null) return Success(existing);

        final operationTransaction =
            await transactions.findByReference('sale-op:$stableOperationId');
        if (operationTransaction is Failure<Transaction?>) {
          return Failure(operationTransaction.error);
        }
        if ((operationTransaction as Success<Transaction?>).value != null) {
          return const Failure(
            AppFailure(
              code: 'sale_operation_conflict',
              message: 'Sale operation has a ledger record but no sale record',
            ),
          );
        }
      }

      final foundCustomer = await customers.findById(customerId);
      if (foundCustomer is Failure<Customer?>) return Failure(foundCustomer.error);
      final customer = (foundCustomer as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active &&
          customer.status != CustomerStatus.provisional) {
        return const Failure(
          AppFailure(
            code: 'customer_not_sellable',
            message: 'Customer is not allowed to buy',
          ),
        );
      }

      final foundCategory = await categories.findById(categoryId);
      if (foundCategory is Failure<CardCategory?>) return Failure(foundCategory.error);
      final category = (foundCategory as Success<CardCategory?>).value;
      if (category == null) {
        return const Failure(
          AppFailure(code: 'category_not_found', message: 'Category was not found'),
        );
      }
      if (!category.isActive) {
        return const Failure(
          AppFailure(code: 'category_inactive', message: 'Category is not active'),
        );
      }

      final balance = await balances.getBalance(
        customerId: customerId,
        currencyCode: category.faceValue.currencyCode,
      );
      if (balance is Failure<Money>) return Failure(balance.error);
      if ((balance as Success<Money>).value.minorUnits < category.faceValue.minorUnits) {
        return const Failure(
          AppFailure(
            code: 'insufficient_balance',
            message: 'Customer balance is insufficient',
          ),
        );
      }

      final now = clock.now();
      final saleId = stableOperationId ?? ids.next('sale');
      final reserved = await inventory.reserveAvailableCard(
        categoryId: categoryId,
        reservationId: ids.next('reservation'),
        now: now,
        expiresAt: now.add(reservationTtl),
      );
      if (reserved is Failure<Card>) return Failure(reserved.error);
      final card = (reserved as Success<Card>).value;

      final sale = Sale(
        id: saleId,
        customerId: customerId,
        cardId: card.id,
        amount: category.faceValue,
        status: TransactionStatus.completed,
        createdAt: now,
      );
      final marked = await cards.markSold(card.id, sale.id);
      if (marked is Failure<void>) return Failure(marked.error);

      final saleTxn = Transaction(
        id: ids.next('txn'),
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: category.faceValue,
        createdAt: now,
        customerId: customerId,
        reference: stableOperationId == null ? sale.id : 'sale-op:$stableOperationId',
      );
      final appended = await transactions.append(saleTxn);
      if (appended is Failure<void>) return Failure(appended.error);

      final savedSale = await sales.save(sale);
      if (savedSale is Failure<void>) return Failure(savedSale.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'sale',
          entityId: sale.id,
          action: 'completed',
          payloadJson:
              '{"cardId":"${card.id}","customerId":"$customerId","operationId":"${stableOperationId ?? ''}"}',
          occurredAt: now,
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(sale);
    });
  }

  @override
  Future<Result<Sale>> sellManual({
    required String phone,
    required String displayName,
    required Money amount,
    required ManualSaleMethod method,
    String? operationId,
  }) {
    return ManualSaleRunner(this).run(
      phone: phone,
      displayName: displayName,
      amount: amount,
      method: method,
      operationId: operationId,
    );
  }

  @override
  Future<Result<Sale>> completeReservedSale({
    required String customerId,
    required String cardId,
    required String reservationId,
    required String operationId,
    Money? saleAmount,
    bool allowNegativeBalance = false,
  }) {
    final stableOperationId = operationId.trim();
    if (stableOperationId.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_operation_id',
            message: 'Sale operation id must not be empty',
          ),
        ),
      );
    }

    return unitOfWork.run(() async {
      final existingSale = await sales.findById(stableOperationId);
      if (existingSale is Failure<Sale?>) return Failure(existingSale.error);
      if ((existingSale as Success<Sale?>).value != null) {
        return Success(existingSale.value!);
      }

      final existingLedger =
          await transactions.findByReference('sale-op:$stableOperationId');
      if (existingLedger is Failure<Transaction?>) return Failure(existingLedger.error);
      if ((existingLedger as Success<Transaction?>).value != null) {
        return const Failure(
          AppFailure(
            code: 'sale_operation_conflict',
            message: 'Sale operation has a ledger record but no sale record',
          ),
        );
      }

      final foundCustomer = await customers.findById(customerId);
      if (foundCustomer is Failure<Customer?>) return Failure(foundCustomer.error);
      final customer = (foundCustomer as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active &&
          customer.status != CustomerStatus.provisional) {
        return const Failure(
          AppFailure(
            code: 'customer_not_sellable',
            message: 'Customer is not allowed to buy',
          ),
        );
      }

      final foundCard = await cards.findById(cardId);
      if (foundCard is Failure<Card?>) return Failure(foundCard.error);
      final card = (foundCard as Success<Card?>).value;
      if (card == null) {
        return const Failure(
          AppFailure(code: 'card_not_found', message: 'Card was not found'),
        );
      }
      if (card.status != CardStatus.reserved ||
          card.reservation.reservationId != reservationId) {
        return const Failure(
          AppFailure(
            code: 'reservation_not_owned',
            message: 'Card is not reserved by this transfer operation',
          ),
        );
      }

      final foundCategory = await categories.findById(card.categoryId);
      if (foundCategory is Failure<CardCategory?>) return Failure(foundCategory.error);
      final category = (foundCategory as Success<CardCategory?>).value;
      if (category == null || !category.isActive) {
        return const Failure(
          AppFailure(
            code: 'category_unavailable',
            message: 'Card category is unavailable',
          ),
        );
      }

      final balance = await balances.getBalance(
        customerId: customerId,
        currencyCode: category.faceValue.currencyCode,
      );
      if (balance is Failure<Money>) return Failure(balance.error);
      final chargeAmount = saleAmount ?? category.faceValue;
      if (!allowNegativeBalance && (balance as Success<Money>).value.minorUnits < chargeAmount.minorUnits) {
        return const Failure(
          AppFailure(
            code: 'insufficient_balance',
            message: 'Customer balance is insufficient',
          ),
        );
      }

      final now = clock.now();
      final sale = Sale(
        id: stableOperationId,
        customerId: customerId,
        cardId: card.id,
        amount: chargeAmount,
        status: TransactionStatus.completed,
        createdAt: now,
      );

      final marked = await cards.markSold(card.id, sale.id);
      if (marked is Failure<void>) return Failure(marked.error);

      final saleTxn = Transaction(
        id: ids.next('txn'),
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: chargeAmount,
        createdAt: now,
        customerId: customerId,
        reference: 'sale-op:$stableOperationId',
      );
      final appended = await transactions.append(saleTxn);
      if (appended is Failure<void>) return Failure(appended.error);

      final saved = await sales.save(sale);
      if (saved is Failure<void>) return Failure(saved.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'sale',
          entityId: sale.id,
          action: 'completed',
          occurredAt: now,
          payloadJson:
              '{"cardId":"${card.id}","customerId":"$customerId","operationId":"$stableOperationId","reservationId":"$reservationId"}',
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(sale);
    });
  }

  @override
  Future<Result<Sale>> reverseSale({required String saleId}) {
    return unitOfWork.run(() async {
      final found = await sales.findById(saleId);
      if (found is Failure<Sale?>) return Failure(found.error);
      final sale = (found as Success<Sale?>).value;
      if (sale == null) {
        return const Failure(
          AppFailure(code: 'sale_not_found', message: 'Sale was not found'),
        );
      }
      if (sale.status != TransactionStatus.completed) {
        return const Failure(
          AppFailure(
            code: 'sale_not_reversible',
            message: 'Sale cannot be reversed',
          ),
        );
      }

      final restored = await cards.restoreAvailable(sale.cardId);
      if (restored is Failure<void>) return Failure(restored.error);

      final original = await transactions.findByReference(sale.id);
      if (original is Failure<Transaction?>) return Failure(original.error);
      Transaction? originalTransaction = (original as Success<Transaction?>).value;
      if (originalTransaction == null) {
        final operationTransaction =
            await transactions.findByReference('sale-op:${sale.id}');
        if (operationTransaction is Failure<Transaction?>) return Failure(operationTransaction.error);
        originalTransaction = (operationTransaction as Success<Transaction?>).value;
      }

      final now = clock.now();
      final reversal = Transaction(
        id: ids.next('txn'),
        type: TransactionType.reversal,
        status: TransactionStatus.completed,
        amount: sale.amount,
        createdAt: now,
        customerId: sale.customerId,
        reference: 'reversal:${sale.id}',
        relatedTransactionId: originalTransaction?.id,
      );
      final appended = await transactions.append(reversal);
      if (appended is Failure<void>) return Failure(appended.error);

      final reversed = Sale(
        id: sale.id,
        customerId: sale.customerId,
        cardId: sale.cardId,
        amount: sale.amount,
        status: TransactionStatus.reversed,
        createdAt: sale.createdAt,
      );
      final saved = await sales.save(reversed);
      if (saved is Failure<void>) return Failure(saved.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'sale',
          entityId: sale.id,
          action: 'reversed',
          occurredAt: now,
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(reversed);
    });
  }
}
