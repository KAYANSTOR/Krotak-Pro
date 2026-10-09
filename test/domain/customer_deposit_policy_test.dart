import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/customer_alternate_code.dart';
import 'package:net_app/domain/services/customer_deposit_block.dart';

void main() {
  test('absent block list allows deposits', () {
    expect(CustomerDepositBlock.isBlocked(null, 'c1'), isFalse);
    expect(CustomerDepositBlock.isBlocked('[]', 'c1'), isFalse);
  });

  test('listed customer is blocked and others stay open', () {
    final raw = CustomerDepositBlock.encode({'c1', 'c2'});
    expect(CustomerDepositBlock.isBlocked(raw, 'c1'), isTrue);
    expect(CustomerDepositBlock.isBlocked(raw, 'c3'), isFalse);
    final next = CustomerDepositBlock.decode(raw)..remove('c1');
    expect(CustomerDepositBlock.isBlocked(CustomerDepositBlock.encode(next), 'c1'), isFalse);
  });

  test('alternate code accepts mixed 4 to 15 and rejects the rest', () {
    expect(CustomerAlternateCode.normalize('ab12'), 'AB12');
    expect(CustomerAlternateCode.normalize('عميل7'), 'عميل7');
    expect(CustomerAlternateCode.normalize('abc'), isNull);
    expect(CustomerAlternateCode.normalize('1234567890123456'), isNull);
    expect(CustomerAlternateCode.normalize('ab 12'), isNull);
  });
}
