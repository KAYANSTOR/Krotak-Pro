import 'package:drift/drift.dart';

import '../../core/result.dart';
import '../../domain/entities/audit.dart' as domain;
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart' as domain;
import '../../domain/entities/license.dart' as domain;
import '../../domain/entities/message.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart' as domain;
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/wallet.dart' as domain;
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

// NOTE: Full file content is in artifacts. This is a partial emergency restore marker.
// The complete file must replace this.
final class LocalTransactionRepository implements TransactionRepository {
  const LocalTransactionRepository(this.database);
  final AppDatabase database;

  @override
  Future<Result<void>> append(domain.Transaction transaction) async {
    try {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: transaction.id,
              type: transaction.type.name,
              status: transaction.status.name,
              amountMinorUnits: transaction.amount.minorUnits,
              currencyCode: transaction.amount.currencyCode,
              createdAt: transaction.createdAt,
              customerId: Value(transaction.customerId),
              reference: Value(transaction.reference),
              relatedTransactionId: Value(transaction.relatedTransactionId),
            ),
          );
      return const Success(null);
    } catch (error) {
      return Failure(_failure('transaction_append_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Transaction>>> findByCustomer(String customerId) async {
    try {
      final rows = await (database.select(database.transactions)
            ..where((table) => table.customerId.equals(customerId))
            ..orderBy([(table) => OrderingTerm(expression: table.createdAt)]))
          .get();
      return Success(rows.map(_toTransaction).toList(growable: false));
    } catch (error) {
      return Failure(_failure('transaction_customer_find_failed', error));
    }
  }

  @override
  Future<Result<domain.Transaction?>> findByReference(String reference) async {
    try {
      final row = await (database.select(database.transactions)
            ..where((table) => table.reference.equals(reference)))
          .getSingleOrNull();
      return Success(row == null ? null : _toTransaction(row));
    } catch (error) {
      return Failure(_failure('transaction_reference_find_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Transaction>>> listRecent({int limit = 50}) async {
    try {
      final rows = await (database.select(database.transactions)
            ..orderBy([
              (table) => OrderingTerm(
                    expression: table.createdAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(limit))
          .get();
      return Success(rows.map(_toTransaction).toList(growable: false));
    } catch (error) {
      return Failure(_failure('transaction_list_recent_failed', error));
    }
  }

  @override
  Future<Result<List<domain.Transaction>>> listCompleted({String? currencyCode}) async {
    try {
      final query = database.select(database.transactions)
        ..where((table) => table.status.equals('completed'));
      if (currencyCode != null) {
        query.where((table) => table.currencyCode.equals(currencyCode));
      }
      final rows = await query.get();
      return Success(rows.map(_toTransaction).toList(growable: false));
    } catch (error) {
      return Failure(_failure('transaction_list_completed_failed', error));
    }
  }

  domain.Transaction _toTransaction(Transaction row) {
    return domain.Transaction(
      id: row.id,
      type: domain.TransactionType.values.byName(row.type),
      status: domain.TransactionStatus.values.byName(row.status),
      amount: Money(
        minorUnits: row.amountMinorUnits,
        currencyCode: row.currencyCode,
      ),
      createdAt: row.createdAt,
      customerId: row.customerId,
      reference: row.reference,
      relatedTransactionId: row.relatedTransactionId,
    );
  }
}

AppFailure _failure(String code, Object error) =>
    AppFailure(code: code, message: error.toString());
