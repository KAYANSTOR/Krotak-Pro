import 'package:flutter_test/flutter_test.dart';

import '../../lib/domain/ledger.dart';
import '../../lib/domain/entities/transaction.dart';

void main() {
  test('advance is a debt direction in the shared ledger', () {
    expect(ledgerDirection(TransactionType.advance), -1);
  });
}
