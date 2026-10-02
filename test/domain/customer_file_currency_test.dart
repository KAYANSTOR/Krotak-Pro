import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/domain/customer_file_currency.dart';
import 'package:net_app/domain/entities/money.dart';
import 'package:net_app/domain/entities/transaction.dart';

void main() {
  test('customer file currencies keep YER and do not mix rows', () {
    final now = DateTime.utc(2026, 10, 2);
    final yer = _tx('a', 'YER', now);
    final usd = _tx('b', 'USD', now.add(const Duration(minutes: 1)));
    final blank = _tx('c', '  ', now);

    final codes = CustomerFileCurrency.availableCodes([usd, blank, yer]);
    expect(codes, ['YER', 'USD']);
    expect(
      CustomerFileCurrency.rowsFor([yer, usd], 'USD').map((t) => t.id),
      ['b'],
    );
    expect(CustomerFileCurrency.keepOrDefault('EUR', codes), 'YER');
    expect(CustomerFileCurrency.keepOrDefault('USD', codes), 'USD');
    expect(CustomerFileCurrency.label('YER'), 'ر.ي');
    expect(CustomerFileCurrency.label('USD'), 'USD');
  });
}

Transaction _tx(String id, String currency, DateTime createdAt) {
  return Transaction(
    id: id,
    customerId: 'c1',
    type: TransactionType.deposit,
    status: TransactionStatus.completed,
    amount: Money(minorUnits: 100, currencyCode: currency),
    createdAt: createdAt,
  );
}
