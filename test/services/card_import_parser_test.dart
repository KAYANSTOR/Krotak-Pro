import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/card_import_parser.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';
import 'package:net_app/domain/services/services.dart';

final class _Settings implements SettingsRepository {
  _Settings([Map<String, String>? values])
      : _values = values ??
            <String, String>{...OutboundTemplateCatalog.initialBodies()};

  final Map<String, String> _values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = _values[key];
    return Success(
      value == null
          ? null
          : AppSetting(key: key, value: value, updatedAt: DateTime.utc(2026, 10, 6)),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    _values[setting.key] = setting.value;
    return const Success(null);
  }
}

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

  group('voucher delivery body comes only from the settings template', () {
    test('includes serial and pin from the stored template', () async {
      final body = await OutboundTemplateRenderer(settings: _Settings())
          .renderVoucherDelivery(serialNumber: '111', secretCode: 'PIN');
      expect(body, isA<Success<String>>());
      final text = (body as Success<String>).value;
      expect(text, contains('111'));
      expect(text, contains('PIN'));
    });

    test('refuses to build a body when the template is not configured', () async {
      final body = await OutboundTemplateRenderer(
        settings: _Settings(<String, String>{}),
      ).renderVoucherDelivery(serialNumber: '111', secretCode: 'PIN');
      expect(body, isA<Failure<String>>());
      expect(
        (body as Failure<String>).error.code,
        'outbound_template_missing',
        reason: 'لا يوجد نص مضمّن بديل في الخدمة',
      );
    });
  });
}
