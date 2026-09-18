import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/card_import_parser.dart';
import 'package:net_app/domain/services/services.dart';

void main() {
  group('CardImportParser serialAndPin', () {
    test('parses comma semicolon and tab', () {
      final r = CardImportParser.parse('''
10001,PINA
10002;PINB
10003\tPINC
''');
      expect(r.drafts.length, 3);
      expect(r.drafts[0].serialNumber, '10001');
      expect(r.drafts[1].secretCode, 'PINB');
      expect(r.errors, isEmpty);
      expect(r.format, CardImportFormat.serialAndPin);
    });

    test('skips blanks comments and header', () {
      final r = CardImportParser.parse('''
serial,pin
# comment

10001,AAAA
''');
      expect(r.drafts.length, 1);
      expect(r.drafts.first.serialNumber, '10001');
    });

    test('reports duplicate serial', () {
      final r = CardImportParser.parse('''
1,A
1,B
''');
      expect(r.drafts.length, 1);
      expect(r.hasErrors, isTrue);
    });

    test('reports incomplete line', () {
      final r = CardImportParser.parse('onlyserial');
      expect(r.hasDrafts, isFalse);
      expect(r.hasErrors, isTrue);
    });
  });

  group('CardImportParser serialOnly', () {
    test('parses one serial per line', () {
      final r = CardImportParser.parse(
        '''
776733907
8273738
99001122
''',
        format: CardImportFormat.serialOnly,
      );
      expect(r.drafts.length, 3);
      expect(r.drafts.every((d) => d.secretCode.isEmpty), isTrue);
      expect(r.drafts.every((d) => d.format == CardImportFormat.serialOnly), isTrue);
      expect(r.errors, isEmpty);
    });

    test('takes first field when delimited', () {
      final r = CardImportParser.parse(
        'ABC123,ignored-pin',
        format: CardImportFormat.serialOnly,
      );
      expect(r.drafts.single.serialNumber, 'ABC123');
      expect(r.drafts.single.secretCode, isEmpty);
    });

    test('reports duplicate serial', () {
      final r = CardImportParser.parse(
        '1\n1\n',
        format: CardImportFormat.serialOnly,
      );
      expect(r.drafts.length, 1);
      expect(r.hasErrors, isTrue);
    });
  });

  group('cardDeliverySmsBody', () {
    test('omits pin line when secret empty', () {
      final body = cardDeliverySmsBody(serialNumber: '111', secretCode: '');
      expect(body, contains('الرقم: 111'));
      expect(body, isNot(contains('الرمز:')));
    });

    test('includes pin when present', () {
      final body = cardDeliverySmsBody(serialNumber: '111', secretCode: 'PIN');
      expect(body, contains('الرمز: PIN'));
    });
  });
}
