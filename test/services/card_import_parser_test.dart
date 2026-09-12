import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/card_import_parser.dart';

void main() {
  group('CardImportParser', () {
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
}
