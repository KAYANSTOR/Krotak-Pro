import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/domain/domain.dart';
import 'package:net_app/domain/repositories/unit_of_work.dart';
import 'package:net_app/domain/services/local_customer_balance_service.dart';
import 'package:net_app/domain/services/services.dart';

import '../helpers/in_memory_repositories.dart';

final class _MemUow implements UnitOfWork {
  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) => action();
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 21, 8, 0, 0);
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

  Future<void> seedCustomer({
    String id = 'c1',
    CustomerStatus status = CustomerStatus.active,
  }) async {
    await customers.save(
      Customer(
        id: id,
        displayName: 'عميل اختبار',
        status: status,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
  }

  test('credit and debit update ledger and write audit with reason', () async {
    await seedCustomer();
    final credit = await balances.credit(
      customerId: 'c1',
      amount: Money(minorUnits: 50000, currencyCode: 'YER'),
      reference: 'manual-credit:1',
      reason: 'دفعة نقدية',
    );
    expect(credit, isA<Success<Transaction>>());

    final debit = await balances.debit(
      customerId: 'c1',
      amount: Money(minorUnits: 15000, currencyCode: 'YER'),
      reference: 'manual-debit:1',
      reason: 'خصم يدوي',
    );
    expect(debit, isA<Success<Transaction>>());

    final bal = await balances.getBalance(customerId: 'c1', currencyCode: 'YER');
    expect((bal as Success<Money>).value.minorUnits, 35000);

    final summary = await balances.getAccountSummary(
      customerId: 'c1',
      currencyCode: 'YER',
    );
    final s = (summary as Success<CustomerAccountSummary>).value;
    expect(s.totalDepositsMinor, 50000);
    expect(s.totalWithdrawalsMinor, 15000);
    expect(s.transactionCount, 2);
  });

  test('provisional customer can be adjusted', () async {
    await seedCustomer(status: CustomerStatus.provisional);
    final r = await balances.credit(
      customerId: 'c1',
      amount: Money(minorUnits: 1000, currencyCode: 'YER'),
      reason: 'تصحيح',
    );
    expect(r, isA<Success<Transaction>>());
  });

  test('blacklisted customer cannot be adjusted', () async {
    await seedCustomer(status: CustomerStatus.blacklisted);
    final r = await balances.debit(
      customerId: 'c1',
      amount: Money(minorUnits: 1000, currencyCode: 'YER'),
      reason: 'محاولة',
    );
    expect(r, isA<Failure<Transaction>>());
  });

  test('idempotent credit by reference', () async {
    await seedCustomer();
    final a = await balances.credit(
      customerId: 'c1',
      amount: Money(minorUnits: 2000, currencyCode: 'YER'),
      reference: 'same-ref',
      reason: 'مرة',
    );
    final b = await balances.credit(
      customerId: 'c1',
      amount: Money(minorUnits: 2000, currencyCode: 'YER'),
      reference: 'same-ref',
      reason: 'مرة',
    );
    expect(a, isA<Success<Transaction>>());
    expect(b, isA<Success<Transaction>>());
    expect((a as Success<Transaction>).value.id, (b as Success<Transaction>).value.id);
  });
}
