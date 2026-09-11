import 'entities/money.dart';
import 'entities/transaction.dart';

int ledgerDirection(TransactionType type) {
  switch (type) {
    case TransactionType.deposit:
    case TransactionType.reward:
    case TransactionType.advance:
    case TransactionType.reversal:
      return 1;
    case TransactionType.withdrawal:
    case TransactionType.sale:
    case TransactionType.settlement:
      return -1;
  }
}

Money sumCompletedLedger({
  required List<Transaction> transactions,
  required String currencyCode,
}) {
  var total = 0;
  for (final transaction in transactions) {
    if (transaction.status != TransactionStatus.completed) continue;
    if (transaction.amount.currencyCode != currencyCode) {
      throw const MixedCurrencyLedger();
    }
    total += transaction.amount.minorUnits * ledgerDirection(transaction.type);
  }
  return Money(minorUnits: total, currencyCode: currencyCode);
}

final class MixedCurrencyLedger implements Exception {
  const MixedCurrencyLedger();
}
