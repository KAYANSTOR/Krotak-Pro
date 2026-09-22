import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/pos_order_message_classifier.dart';

void main() {
  test('recognizes POS order to the POS', () {
    expect(PosOrderMessageClassifier.isCardOrder('3 كروت 100'), isTrue);
    expect(PosOrderMessageClassifier.isCardOrder('1 كرت 100'), isTrue);
    expect(PosOrderMessageClassifier.isCardOrder('٣ كروت ١٠٠'), isTrue);
  });

  test('recognizes POS order to a customer', () {
    expect(
      PosOrderMessageClassifier.isCardOrder('3 كروت 100 779776919'),
      isTrue,
    );
  });

  test('rejects legacy phone-first and financial transfer text', () {
    expect(
      PosOrderMessageClassifier.isCardOrder('779776919 100 3'),
      isFalse,
    );
    expect(
      PosOrderMessageClassifier.isCardOrder('تم تحويل 100 ريال الى 779776919'),
      isFalse,
    );
  });
}
