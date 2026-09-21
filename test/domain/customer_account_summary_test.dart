import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/customer_account_summary.dart';
import 'package:net_app/domain/entities/advance.dart';
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
      createdAt: DateTime(2026, 9, 21),
      customerId: 'c1',
    );
  }

  test('summarizes real ledger totals and ignores pending rows', () {
    final summary = CustomerAccountSummary.fromLedger(
      transactions: [
        tx(id: 'd1', type: TransactionType.deposit, minor: 10000),
        tx(id: 's1', type: TransactionType.sale, minor: 15000),
        tx(id: 'w1', type: TransactionType.withdrawal, minor: 2000),
        tx(id: 'p1', type: TransactionType.deposit, minor: 5000, status: TransactionStatus.pending),
      ],
      advances: [
        Advance(
          id: 'a1',
          customerId: 'c1',
          cardId: 'card-1',
          amount: m(3000),
          outstanding: m(3000),
          reference: 'salafni:1',
          createdAt: DateTime(2026, 9, 21),
          status: AdvanceStatus.open,
        ),
      ],
      currencyCode: yer,
    );

    expect(summary.balance.minorUnits, 10000 - 15000 - 2000);
    expect(summary.totalPayments.minorUnits, 10000);
    expect(summary.totalSales.minorUnits, 15000);
    expect(summary.totalDebt.minorUnits, 15000 + 2000);
    expect(summary.openAdvanceCount, 1);
    expect(summary.openAdvances.minorUnits, 3000);
  });
}
