import 'entities/advance.dart';
import 'entities/money.dart';
import 'entities/transaction.dart';
import 'ledger.dart';

/// ملخص دفتر حقيقي لملف العميل — بدون أرقام ثابتة.
final class CustomerAccountSummary {
  const CustomerAccountSummary({
    required this.balance,
    required this.totalDebt,
    required this.totalPayments,
    required this.totalSales,
    required this.openAdvances,
    required this.openAdvanceCount,
  });

  final Money balance;
  final Money totalDebt;
  final Money totalPayments;
  final Money totalSales;
  final Money openAdvances;
  final int openAdvanceCount;

  static CustomerAccountSummary fromLedger({
    required List<Transaction> transactions,
    required List<Advance> advances,
    required String currencyCode,
  }) {
    final completed = transactions
        .where((tx) => tx.status == TransactionStatus.completed)
        .toList(growable: false);

    final balance = sumCompletedLedger(
      transactions: completed,
      currencyCode: currencyCode,
    );

    var debt = 0;
    var payments = 0;
    var sales = 0;
    for (final tx in completed) {
      if (tx.amount.currencyCode != currencyCode) {
        throw const MixedCurrencyLedger();
      }
      switch (tx.type) {
        case TransactionType.sale:
        case TransactionType.advance:
        case TransactionType.withdrawal:
          debt += tx.amount.minorUnits;
        case TransactionType.deposit:
        case TransactionType.reward:
          payments += tx.amount.minorUnits;
        case TransactionType.settlement:
          payments += tx.amount.minorUnits;
        case TransactionType.reversal:
          break;
      }
      if (tx.type == TransactionType.sale) {
        sales += tx.amount.minorUnits;
      }
    }

    var openAdvanceMinor = 0;
    var openCount = 0;
    for (final advance in advances) {
      if (advance.status != AdvanceStatus.open) continue;
      if (advance.outstanding.currencyCode != currencyCode) continue;
      openAdvanceMinor += advance.outstanding.minorUnits;
      openCount += 1;
    }

    return CustomerAccountSummary(
      balance: balance,
      totalDebt: Money(minorUnits: debt, currencyCode: currencyCode),
      totalPayments: Money(minorUnits: payments, currencyCode: currencyCode),
      totalSales: Money(minorUnits: sales, currencyCode: currencyCode),
      openAdvances: Money(minorUnits: openAdvanceMinor, currencyCode: currencyCode),
      openAdvanceCount: openCount,
    );
  }
}
