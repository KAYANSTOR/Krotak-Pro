import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/entities/transaction.dart';
import 'package:net_app/domain/ledger.dart';

void main() {
  test('advance is a debt direction in the shared ledger', () {
    expect(ledgerDirection(TransactionType.advance), -1);
  });
}
