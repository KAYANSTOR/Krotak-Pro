import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/customer_account_summary.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';

void main() {
  const yer = 'YER';
  Money m(int minor) => Money(minorUnits: minor, currencyCode: yer);

  Transaction tx({
    required String id,
    required TransactionType type,
    required int minor,
    TransactionStatus status = TransactionStatus.completed,
  }) {
    return Transaction(
      id: id,
      type: type,
      status: status,
      amount: m(minor),
      createdAt: DateTime.utc(2026, 9, 21),
      customerId: 'c1',
    );
  }

  test('aggregates real ledger totals without placeholder numbers', () {
    final rows = [
      tx(id: 'd1', type: TransactionType.deposit, minor: 100000),
      tx(id: 's1', type: TransactionType.sale, minor: 40000),
      tx(id: 's2', type: TransactionType.sale, minor: 25000),
      tx(id: 'p1', type: TransactionType.deposit, minor: 5000, status: TransactionStatus.pending),
    ];
    final summary = CustomerAccountSummary.fromLedger(
      transactions: rows,
      currencyCode: yer,
      openAdvancesMinor: 15000,
    );
    expect(summary.totalPaymentsMinor, 100000);
    expect(summary.totalSalesMinor, 65000);
    expect(summary.balance.minorUnits, 100000 - 65000);
    expect(summary.totalDebtMinor, 0);
    expect(summary.openAdvancesMinor, 15000);
  });

  test('debt is the absolute negative completed balance', () {
    final rows = [
      tx(id: 's1', type: TransactionType.sale, minor: 80000),
      tx(id: 'd1', type: TransactionType.deposit, minor: 20000),
    ];
    final summary = CustomerAccountSummary.fromLedger(
      transactions: rows,
      currencyCode: yer,
    );
    expect(summary.balance.minorUnits, -60000);
    expect(summary.totalDebtMinor, 60000);
    expect(summary.totalPaymentsMinor, 20000);
    expect(summary.totalSalesMinor, 80000);
  });
}
