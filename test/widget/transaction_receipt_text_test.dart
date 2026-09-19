import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/widgets/net/net_transaction_detail_sheet.dart';

void main() {
  test('buildTransactionReceiptText lists amount reference and beneficiary', () {
    final text = buildTransactionReceiptText(
      amountText: '100.00',
      currencyLabel: 'ر.ي',
      reference: '17902153066372',
      typeLabel: 'إيداع / تحويل',
      statusLabel: 'مكتملة',
      dateLabel: '18/09/2026 (3:49 ص)',
      beneficiaryLabel: 'غير مرتبط بحساب',
    );
    expect(text, contains('NET — بيانات الحركة'));
    expect(text, contains('17902153066372'));
    expect(text, contains('100.00 ر.ي'));
    expect(text, contains('غير مرتبط بحساب'));
    expect(text.split('\n').length, 7);
  });
}
