import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/salafni_customer_ceiling.dart';

void main() {
  test('absent or empty ceiling means no per-customer limit', () {
    expect(SalafniCustomerCeiling.forCustomer(null, 'c1'), isNull);
    expect(SalafniCustomerCeiling.forCustomer('', 'c1'), isNull);
    expect(SalafniCustomerCeiling.forCustomer('{}', 'c1'), isNull);
  });

  test('zero blocks and a positive value is the minor-unit ceiling', () {
    final raw = SalafniCustomerCeiling.encode({
      'c1': 0,
      'c2': 10000,
    });
    expect(SalafniCustomerCeiling.forCustomer(raw, 'c1'), 0);
    expect(SalafniCustomerCeiling.forCustomer(raw, 'c2'), 10000);
    expect(SalafniCustomerCeiling.forCustomer(raw, 'c3'), isNull);
  });

  test('invalid entries are dropped and other customers stay intact', () {
    final raw = SalafniCustomerCeiling.encode({
      'c1': 5000,
      '': 100,
    });
    final next = Map<String, int>.from(SalafniCustomerCeiling.decode(raw))
      ..remove('c1');
    expect(SalafniCustomerCeiling.decode(SalafniCustomerCeiling.encode(next)), isEmpty);
  });
}
