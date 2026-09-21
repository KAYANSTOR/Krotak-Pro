import 'package:flutter_test/flutter_test.dart';
import 'package:krotak_pro/domain/entities/money.dart';
import 'package:krotak_pro/domain/entities/transaction.dart';
import 'package:krotak_pro/domain/ledger.dart';

void main() {
  test('completed deposits increase and sales decrease the ledger', () {
    final transactions = [
      Transaction(
        id: 'd1',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 1000, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 1),
      ),
      Transaction(
        id: 's1',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 250, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 2),
      ),
      Transaction(
        id: 'p1',
        type: TransactionType.sale,
        status: TransactionStatus.pending,
        amount: const Money(minorUnits: 250, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 3),
      ),
    ];

    final balance = sumCompletedLedger(
      transactions: transactions,
      currencyCode: 'YER',
    );

    expect(balance, const Money(minorUnits: 750, currencyCode: 'YER'));
  });

  test('reversal restores a completed sale', () {
    final transactions = [
      Transaction(
        id: 'd1',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 500, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 1),
      ),
      Transaction(
        id: 's1',
        type: TransactionType.sale,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 200, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 2),
      ),
      Transaction(
        id: 'r1',
        type: TransactionType.reversal,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 200, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 3),
        relatedTransactionId: 's1',
      ),
    ];

    expect(
      sumCompletedLedger(transactions: transactions, currencyCode: 'YER'),
      const Money(minorUnits: 500, currencyCode: 'YER'),
    );
  });

  test('mixed currencies are rejected', () {
    final transactions = [
      Transaction(
        id: 'd1',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 100, currencyCode: 'YER'),
        createdAt: DateTime(2026, 1, 1),
      ),
      Transaction(
        id: 'd2',
        type: TransactionType.deposit,
        status: TransactionStatus.completed,
        amount: const Money(minorUnits: 100, currencyCode: 'USD'),
        createdAt: DateTime(2026, 1, 2),
      ),
    ];

    expect(
      () => sumCompletedLedger(transactions: transactions, currencyCode: 'YER'),
      throwsA(isA<MixedCurrencyLedger>()),
    );
  });
}
