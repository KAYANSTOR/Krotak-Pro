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
import 'services.dart';

final class LocalSaleService implements SaleService {
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
  final Duration reservationTtl;

  @override
  Future<Result<Sale>> sellFromBalance({
    required String customerId,
    required String categoryId,
  }) {
    return unitOfWork.run(() async {
      final foundCustomer = await customers.findById(customerId);
      if (foundCustomer is Failure<Customer?>) return Failure(foundCustomer.error);
      final customer = (foundCustomer as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(
            code: 'customer_not_sellable',
            message: 'Customer is not allowed to buy',
          ),
        );
      }

      final foundCategory = await categories.findById(categoryId);
      if (foundCategory is Failure<CardCategory?>) {
        return Failure(foundCategory.error);
      }
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
          AppFailure(code: 'insufficient_balance', message: 'Customer balance is insufficient'),
        );
      }

      final now = clock.now();
      final reserved = await inventory.reserveAvailableCard(
        categoryId: categoryId,
        reservationId: ids.next('reservation'),
        now: now,
        expiresAt: now.add(reservationTtl),
      );
      if (reserved is Failure<Card>) return Failure(reserved.error);
      final card = (reserved as Success<Card>).value;

      final sale = Sale(
        id: ids.next('sale'),
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
        reference: sale.id,
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
          payloadJson: '{"cardId":"${card.id}","customerId":"$customerId"}',
          occurredAt: now,
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
          AppFailure(code: 'sale_not_reversible', message: 'Sale cannot be reversed'),
        );
      }

      final restored = await cards.restoreAvailable(sale.cardId);
      if (restored is Failure<void>) return Failure(restored.error);

      final original = await transactions.findByReference(sale.id);
      if (original is Failure<Transaction?>) return Failure(original.error);

      final now = clock.now();
      final reversal = Transaction(
        id: ids.next('txn'),
        type: TransactionType.reversal,
        status: TransactionStatus.completed,
        amount: sale.amount,
        createdAt: now,
        customerId: sale.customerId,
        reference: 'reversal:${sale.id}',
        relatedTransactionId: (original as Success<Transaction?>).value?.id,
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
