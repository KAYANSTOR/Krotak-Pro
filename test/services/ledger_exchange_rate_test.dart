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

  test('quotes debtor and creditor sides and names a currency without a rate', () {
    final quote = LedgerExchangeRate.quoteSides(
      debtorByCurrency: const {'YER': 10000, 'USD': 200, 'EUR': 50},
      creditorByCurrency: const {'SAR': 100, 'EUR': 25},
      targetCurrency: 'YER',
      rates: const {'USD': 50000, 'SAR': 14000},
    );
    expect(quote.debtorMinorUnits, 110000);
    expect(quote.creditorMinorUnits, 14000);
    expect(quote.missingCurrencies, ['EUR']);
    expect(quote.complete, isFalse);
  });
}

  test('pins a movement rate so a later display rate does not rewrite it', () {
    final saved = LedgerExchangeRate.encodePin(
      null,
      transactionId: 'tx-1',
      currencyCode: 'usd',
      ratePerMajor: 50000,
    );
    final pins = LedgerExchangeRate.decodePins(saved);
    expect(pins['tx-1']?.yerMinorPerMajor, 50000);

    final quote = LedgerExchangeRate.quoteMovements(
      movements: [
        RatedMovement(
          currencyCode: 'USD',
          signedMinorUnits: 100,
          pinnedRate: pins['tx-1']?.yerMinorPerMajor,
        ),
        const RatedMovement(currencyCode: 'YER', signedMinorUnits: 10000),
      ],
      targetCurrency: 'YER',
      rates: const {'USD': 90000},
    );
    expect(quote.minorUnits, 60000);
    expect(quote.complete, isTrue);

    final cleared = LedgerExchangeRate.encodePin(
      saved,
      transactionId: 'tx-1',
      currencyCode: 'USD',
      ratePerMajor: 0,
    );
    expect(LedgerExchangeRate.decodePins(cleared), isEmpty);
  });
