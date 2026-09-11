import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import '../ledger.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';

/// Settlement: debit completed balance for a customer (e.g. POS settlement).
///
/// Rules (temporary product assumptions):
/// - customer must be active
/// - amount must be positive and same currency as existing ledger
/// - available completed balance must cover the amount
/// - atomic: transaction append + audit
final class LocalSettlementService {
  const LocalSettlementService({
    required this.customers,
    required this.transactions,
    required this.auditLogs,
    required this.unitOfWork,
    required this.clock,
    required this.ids,
  });

  final CustomerRepository customers;
  final TransactionRepository transactions;
  final AuditLogRepository auditLogs;
  final UnitOfWork unitOfWork;
  final Clock clock;
  final IdGenerator ids;

  Future<Result<Transaction>> settle({
    required String customerId,
    required Money amount,
    String? reference,
  }) {
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_amount', message: 'Settlement amount must be positive'),
        ),
      );
    }

    return unitOfWork.run(() async {
      final found = await customers.findById(customerId);
      if (found is Failure<Customer?>) return Failure(found.error);
      final customer = (found as Success<Customer?>).value;
      if (customer == null) {
        return const Failure(
          AppFailure(code: 'customer_not_found', message: 'Customer was not found'),
        );
      }
      if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(code: 'customer_not_active', message: 'Only active customers can settle'),
        );
      }

      final rows = await transactions.findByCustomer(customerId);
      if (rows is Failure<List<Transaction>>) return Failure(rows.error);
      final ledger = (rows as Success<List<Transaction>>).value;

      final Money balance;
      try {
        balance = sumCompletedLedger(
          transactions: ledger,
          currencyCode: amount.currencyCode,
        );
      } on StateError catch (e) {
        return Failure(AppFailure(code: 'currency_mismatch', message: e.message));
      }

      if (balance.minorUnits < amount.minorUnits) {
        return const Failure(
          AppFailure(code: 'insufficient_balance', message: 'Balance does not cover settlement'),
        );
      }

      if (reference != null && reference.isNotEmpty) {
        final existing = await transactions.findByReference(reference);
        if (existing is Failure<Transaction?>) return Failure(existing.error);
        final prior = (existing as Success<Transaction?>).value;
        if (prior != null) {
          if (prior.customerId == customerId &&
              prior.amount.minorUnits == amount.minorUnits &&
              prior.amount.currencyCode == amount.currencyCode &&
              prior.type == TransactionType.settlement) {
            return Success(prior);
          }
          return const Failure(
            AppFailure(code: 'duplicate_reference', message: 'Settlement reference already used'),
          );
        }
      }

      final tx = Transaction(
        id: ids.next('tx'),
        type: TransactionType.settlement,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now(),
        customerId: customerId,
        reference: reference,
      );
      final saved = await transactions.append(tx);
      if (saved is Failure<void>) return Failure(saved.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'transaction',
          entityId: tx.id,
          action: 'settlement',
          payloadJson: '{"customerId":"$customerId","minorUnits":${amount.minorUnits}}',
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(tx);
    });
  }
}
