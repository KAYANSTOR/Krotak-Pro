import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/customer_account_currency.dart';

void main() {
  test('stores a non-default currency and clears back to YER', () {
    final saved = CustomerAccountCurrency.encodeMap(
      null,
      customerId: 'c1',
      currencyCode: 'usd',
    );
    expect(CustomerAccountCurrency.lookup(saved, 'c1'), 'USD');
    expect(
      CustomerAccountCurrency.preferred(saved, 'c1', const ['YER', 'USD']),
      'USD',
    );

    final cleared = CustomerAccountCurrency.encodeMap(
      saved,
      customerId: 'c1',
      currencyCode: 'YER',
    );
    expect(CustomerAccountCurrency.lookup(cleared, 'c1'), isNull);
    expect(
      CustomerAccountCurrency.preferred(cleared, 'c1', const ['YER', 'USD']),
      'YER',
    );
  });

  test('rejects an unknown code and ignores another customer', () {
    final saved = CustomerAccountCurrency.encodeMap(
      null,
      customerId: 'c1',
      currencyCode: 'ريال',
    );
    expect(CustomerAccountCurrency.lookup(saved, 'c1'), isNull);
    final usd = CustomerAccountCurrency.encodeMap(
      saved,
      customerId: 'c1',
      currencyCode: 'SAR',
    );
    expect(CustomerAccountCurrency.lookup(usd, 'c2'), isNull);
  });

  test('keeps the stored currency visible even without ledger rows', () {
    expect(
      CustomerAccountCurrency.withPreferred(const ['YER'], 'SAR'),
      ['YER', 'SAR'],
    );
    expect(
      CustomerAccountCurrency.preferred('{"c1":"SAR"}', 'c1', const ['YER']),
      'YER',
    );
  });
}
