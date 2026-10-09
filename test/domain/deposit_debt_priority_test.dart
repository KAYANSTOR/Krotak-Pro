import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/deposit_debt_priority.dart';

void main() {
  test('an untouched deposit still follows the card path', () {
    expect(
      DepositDebtPriority.decide(appliedMinorUnits: 0, remainingMinorUnits: 50000),
      DepositAfterDebt.deliverCard,
    );
  });

  test('a deposit fully consumed by debt does not send a card', () {
    expect(
      DepositDebtPriority.decide(appliedMinorUnits: 50000, remainingMinorUnits: 0),
      DepositAfterDebt.settlementOnly,
    );
  });

  test('a partial settlement keeps the surplus as balance, not a card', () {
    expect(
      DepositDebtPriority.decide(appliedMinorUnits: 20000, remainingMinorUnits: 30000),
      DepositAfterDebt.creditSurplusNoCard,
    );
  });
}
