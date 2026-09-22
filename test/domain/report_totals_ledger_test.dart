import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/domain/domain.dart';
import 'package:net_app/domain/ledger.dart';
import 'package:net_app/domain/repositories/unit_of_work.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';

import '../helpers/in_memory_repositories.dart';

final class _MemUow implements UnitOfWork {
  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 22, 10);
}

final class _SeqIds implements IdGenerator {
  var n = 0;
  @override
  String next(String prefix) {
    n++;
    return '$prefix-$n';
  }
}

void main() {
  late InMemoryCustomerRepository customers;
  late InMemoryTransactionRepository transactions;
  late InMemoryAuditLogRepository audits;
  late LocalCustomerBalanceService balances;

  setUp(() {
    customers = InMemoryCustomerRepository();
    transactions = InMemoryTransactionRepository();
    audits = InMemoryAuditLogRepository();
    balances = LocalCustomerBalanceService(
      customers: customers,
      transactions: transactions,
      auditLogs: audits,
      unitOfWork: _MemUow(),
      clock: _FixedClock(),
      ids: _SeqIds(),
    );
  });

  test('getTotalOutstanding matches sumCompletedLedger over completed rows',
      () async {
    Future<void> seed(String id, String name) async {
      await customers.save(
        Customer(
          id: id,
          displayName: name,
          status: CustomerStatus.active,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );
    }

    await seed('c1', 'أ');
    await seed('c2', 'ب');

    await balances.credit(
      customerId: 'c1',
      amount: const Money(minorUnits: 10_000, currencyCode: 'YER'),
      reference: 't1',
      reason: 'إيداع',
    );
    await balances.debit(
      customerId: 'c1',
      amount: const Money(minorUnits: 3_000, currencyCode: 'YER'),
      reference: 't2',
      reason: 'خصم',
    );
    await balances.credit(
      customerId: 'c2',
      amount: const Money(minorUnits: 5_000, currencyCode: 'YER'),
      reference: 't3',
      reason: 'إيداع',
    );

    final total = await balances.getTotalOutstanding(currencyCode: 'YER');
    expect(total, isA<Success<Money>>());
    final money = (total as Success<Money>).value;
    expect(money.minorUnits, 12_000);

    final all = await transactions.listCompleted(currencyCode: 'YER');
    final rows = (all as Success<List<Transaction>>).value;
    final recomputed =
        sumCompletedLedger(transactions: rows, currencyCode: 'YER');
    expect(recomputed.minorUnits, money.minorUnits);
  });
}
