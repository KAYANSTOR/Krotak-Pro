import 'entities/transaction.dart';
import 'entities/money.dart';
import 'ledger.dart';

/// ملخص دفتر العميل من الحركات الحقيقية فقط — بدون أرقام ثابتة.
final class CustomerAccountSummary {
  const CustomerAccountSummary({
    required this.balance,
    required this.totalDebtMinor,
    required this.totalPaymentsMinor,
    required this.totalSalesMinor,
    required this.openAdvancesMinor,
    required this.currencyCode,
  });

  final Money balance;
  final int totalDebtMinor;
  final int totalPaymentsMinor;
  final int totalSalesMinor;
  final int openAdvancesMinor;
  final String currencyCode;

  static CustomerAccountSummary fromLedger({
    required List<Transaction> transactions,
    required String currencyCode,
    int openAdvancesMinor = 0,
  }) {
    final completed = transactions
        .where((t) => t.status == TransactionStatus.completed)
        .where((t) => t.amount.currencyCode == currencyCode)
        .toList();
    var payments = 0;
    var sales = 0;
    var debtish = 0;
    for (final t in completed) {
      final units = t.amount.minorUnits;
      switch (t.type) {
        case TransactionType.deposit:
        case TransactionType.reward:
          payments += units;
        case TransactionType.sale:
          sales += units;
          if (ledgerDirection(t.type) < 0) debtish += units;
        case TransactionType.advance:
          if (ledgerDirection(t.type) < 0) debtish += units;
        case TransactionType.withdrawal:
        case TransactionType.settlement:
        case TransactionType.reversal:
          break;
      }
    }
    final balance = sumCompletedLedger(
      transactions: transactions,
      currencyCode: currencyCode,
    );
    final debt = balance.minorUnits < 0 ? -balance.minorUnits : 0;
    return CustomerAccountSummary(
      balance: balance,
      totalDebtMinor: debt,
      totalPaymentsMinor: payments,
      totalSalesMinor: sales,
      openAdvancesMinor: openAdvancesMinor,
      currencyCode: currencyCode,
    );
  }
}
