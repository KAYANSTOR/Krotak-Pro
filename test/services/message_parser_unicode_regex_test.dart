import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/message.dart';
import 'package:net_app/domain/services/local_message_parser.dart';

/// Regression: template patterns containing `:` `-` `.` (e.g. the seeded
/// wallet template) used to produce invalid escapes (`\:` / `\-`) under
/// `unicode: true`, throwing FormatException on the rejected/pending screens.
void main() {
  group('LocalMessageParser unicode-safe pattern regex', () {
    const template = TransferTemplate(
      id: 'wallet-colon-dash',
      name: 'Wallet colon/dash pattern',
      pattern: 'اضيف {amount} ر.ي تحويل مشترك رص:{ref} ر.ي من {account}-{phone}',
      isActive: true,
    );
    final parser = LocalMessageParser(templates: const [template]);

    IncomingMessage messageWith(String body) => IncomingMessage(
          id: 'm-unicode',
          sender: '777',
          body: body,
          receivedAt: DateTime.utc(2026, 1, 1),
          status: MessageProcessingStatus.received,
        );

    test('parses a body matching a pattern with colon, dash and dots', () {
      final result = parser.parse(
        messageWith(
          'اضيف 5000 ر.ي تحويل مشترك رص:5500.36 ر.ي من وليد العمري-770455491',
        ),
      );

      expect(result, isA<Success<ParsedTransfer>>());
      final parsed = (result as Success<ParsedTransfer>).value;
      expect(parsed.amount.minorUnits, 500000);
      expect(parsed.customerIdentifier, '770455491');
      expect(parsed.reference, '5500.36');
    });

    test('parse never throws, even for unrelated bodies', () {
      expect(
        () => parser.parse(messageWith('رسالة لا تطابق أي قالب: - / , .')),
        returnsNormally,
      );
    });
  });
}
