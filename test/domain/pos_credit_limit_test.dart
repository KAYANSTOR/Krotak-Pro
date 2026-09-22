import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/pos_account.dart';
import 'package:net_app/domain/entities/wallet.dart';
import 'package:net_app/domain/rejection_codes.dart';
import 'package:net_app/domain/services/pos_credit_limit.dart';

PosAccount _pos({int? limit}) => PosAccount(
      posId: 'pos-1',
      customerId: 'cust-1',
      name: 'نقطة أ',
      identifiers: const ['777000111'],
      creditLimitMinorUnits: limit,
    );

void main() {
  test('null limit is unlimited', () {
    expect(
      PosCreditLimit.evaluate(
        account: _pos(),
        currentBalanceMinor: -9_999_999,
        additionalChargeMinor: 100,
      ),
      isNull,
    );
  });

  test('zero limit blocks any new debt', () {
    final failure = PosCreditLimit.evaluate(
      account: _pos(limit: 0),
      currentBalanceMinor: 0,
      additionalChargeMinor: 100,
    );
    expect(failure?.code, RejectionCodes.creditLimitExceeded);
  });

  test('allows order that stays within remaining headroom', () {
    expect(
      PosCreditLimit.evaluate(
        account: _pos(limit: 10_000),
        currentBalanceMinor: -4_000,
        additionalChargeMinor: 6_000,
      ),
      isNull,
    );
  });

  test('rejects order that would exceed remaining headroom', () {
    final failure = PosCreditLimit.evaluate(
      account: _pos(limit: 10_000),
      currentBalanceMinor: -4_000,
      additionalChargeMinor: 6_001,
    );
    expect(failure?.code, RejectionCodes.creditLimitExceeded);
  });

  test('settling debt increases available headroom', () {
    expect(
      PosCreditLimit.remainingHeadroomMinor(
        account: _pos(limit: 10_000),
        currentBalanceMinor: -8_000,
      ),
      2_000,
    );
    expect(
      PosCreditLimit.remainingHeadroomMinor(
        account: _pos(limit: 10_000),
        currentBalanceMinor: 0,
      ),
      10_000,
    );
  });

  test('multi-quantity charge uses total additional amount', () {
    // limit 10000, debt 9000, unit 500 × qty 3 = 1500 → exceeds
    final failure = PosCreditLimit.evaluate(
      account: _pos(limit: 10_000),
      currentBalanceMinor: -9_000,
      additionalChargeMinor: 500 * 3,
    );
    expect(failure?.code, RejectionCodes.creditLimitExceeded);
    expect(
      PosCreditLimit.evaluate(
        account: _pos(limit: 10_000),
        currentBalanceMinor: -9_000,
        additionalChargeMinor: 500 * 2,
      ),
      isNull,
    );
  });
}
