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
import 'services.dart';

final class LocalCustomerBalanceService implements CustomerBalanceService {
  const LocalCustomerBalanceService({
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

  @override
  Future<Result<Money>> getBalance({
    required String customerId,
    required String currencyCode,
  }) async {
    final rows = await transactions.findByCustomer(customerId);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    try {
      return Success(
        sumCompletedLedger(
          transactions: (rows as Success<List<Transaction>>).value,
          currencyCode: currencyCode,
        ),
      );
    } on MixedCurrencyLedger {
      return const Failure(
        AppFailure(
          code: 'mixed_currency',
          message: 'Customer ledger contains mixed currencies',
        ),
      );
    }
  }

  @override
  Future<Result<Money>> getTotalOutstanding({required String currencyCode}) async {
    final rows = await transactions.listCompleted(currencyCode: currencyCode);
    if (rows is Failure<List<Transaction>>) return Failure(rows.error);
    try {
      return Success(
        sumCompletedLedger(
          transactions: (rows as Success<List<Transaction>>).value,
          currencyCode: currencyCode,
        ),
      );
    } on MixedCurrencyLedger {
      return const Failure(
        AppFailure(
          code: 'mixed_currency',
          message: 'Ledger contains mixed currencies',
        ),
      );
    }
  }

  @override
  Future<Result<Transaction>> credit({
    required String customerId,
    required Money amount,
    String? reference,
    String? reason,
  }) {
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_amount', message: 'Credit amount must be positive'),
        ),
      );
    }

    return unitOfWork.run(() async {
      if (reference != null) {
        final existing = await transactions.findByReference(reference);
        if (existing is Failure<Transaction?>) return Failure(existing.error);
        final current = (existing as Success<Transaction?>).value;
        if (current != null) {
          if (current.customerId == customerId && current.amount == amount) {
            return Success(current);
          }
          return const Failure(
            AppFailure(
              code: 'duplicate_reference',
              message: 'Reference already exists',
            ),
          );
        }
      }

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
          AppFailure(
            code: 'customer_not_active',
            message: 'Only active customers can be credited',
          ),
        );
      }

      final transaction = Transaction(
        id: ids.next('txn'),
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now(),
        customerId: customerId,
        reference: reference,
      );
      final appended = await transactions.append(transaction);
      if (appended is Failure<void>) return Failure(appended.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'transaction',
          entityId: transaction.id,
          action: 'credited',
          payloadJson: _payload(customerId: customerId, reason: reason, amount: amount),
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(transaction);
    });
  }

  @override
  Future<Result<Transaction>> debit({
    required String customerId,
    required Money amount,
    String? reference,
    String? reason,
  }) {
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_amount', message: 'Debit amount must be positive'),
        ),
      );
    }

    return unitOfWork.run(() async {
      if (reference != null) {
        final existing = await transactions.findByReference(reference);
        if (existing is Failure<Transaction?>) return Failure(existing.error);
        final current = (existing as Success<Transaction?>).value;
        if (current != null) {
          if (current.customerId == customerId &&
              current.amount == amount &&
              current.type == TransactionType.withdrawal) {
            return Success(current);
          }
          return const Failure(
            AppFailure(
              code: 'duplicate_reference',
              message: 'Reference already exists',
            ),
          );
        }
      }

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
          AppFailure(
            code: 'customer_not_active',
            message: 'Only active customers can be debited',
          ),
        );
      }

      final transaction = Transaction(
        id: ids.next('txn'),
        type: TransactionType.withdrawal,
        status: TransactionStatus.completed,
        amount: amount,
        createdAt: clock.now(),
        customerId: customerId,
        reference: reference,
      );
      final appended = await transactions.append(transaction);
      if (appended is Failure<void>) return Failure(appended.error);

      final audited = await auditLogs.append(
        AuditLog(
          id: ids.next('audit'),
          entityType: 'transaction',
          entityId: transaction.id,
          action: 'debited',
          payloadJson: _payload(customerId: customerId, reason: reason, amount: amount),
          occurredAt: clock.now(),
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);
      return Success(transaction);
    });
  }

  String _payload({
    required String customerId,
    required Money amount,
    String? reason,
  }) {
    final safeReason = (reason ?? '').replaceAll('"', r'\"').trim();
    return '{"customerId":"$customerId","minorUnits":${amount.minorUnits},"reason":"$safeReason"}';
  }
}
