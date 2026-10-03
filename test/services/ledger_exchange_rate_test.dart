import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/ledger_exchange_rate.dart';

void main() {
  test('stores a positive YER rate and clears it', () {
    final saved = LedgerExchangeRate.encodeMap(
      null,
      currencyCode: 'usd',
      ratePerMajor: 53500,
    );
    expect(LedgerExchangeRate.lookup(saved, 'USD'), 53500);
    expect(LedgerExchangeRate.lookup(saved, 'YER'), isNull);

    final cleared = LedgerExchangeRate.encodeMap(
      saved,
      currencyCode: 'USD',
      ratePerMajor: 0,
    );
    expect(LedgerExchangeRate.lookup(cleared, 'USD'), isNull);
  });

  test('rejects an unknown code and a non-positive rate', () {
    final saved = LedgerExchangeRate.encodeMap(
      null,
      currencyCode: 'ريال',
      ratePerMajor: 100,
    );
    expect(saved, '{}');
    expect(
      LedgerExchangeRate.normalizeRate(-1),
      isNull,
    );
  });

  test('converts through YER without rewriting a missing rate into zero', () {
    const rates = {'USD': 50000, 'SAR': 14000};
    expect(
      LedgerExchangeRate.convertMinor(
        minorUnits: 200,
        from: 'USD',
        to: 'YER',
        rates: rates,
      ),
      100000,
    );
    expect(
      LedgerExchangeRate.convertMinor(
        minorUnits: 100000,
        from: 'YER',
        to: 'SAR',
        rates: rates,
      ),
      714,
    );
    expect(
      LedgerExchangeRate.convertMinor(
        minorUnits: 100,
        from: 'EUR',
        to: 'YER',
        rates: rates,
      ),
      isNull,
    );

    final quote = LedgerExchangeRate.quote(
      balancesByCurrency: const {'YER': 10000, 'USD': 100, 'EUR': 50},
      targetCurrency: 'YER',
      rates: rates,
    );
    expect(quote.minorUnits, 60000);
    expect(quote.missingCurrencies, ['EUR']);
    expect(quote.complete, isFalse);
  });
}
