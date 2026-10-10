import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

final class _Settings implements SettingsRepository {
  _Settings([Map<String, String>? values]) : _values = values ?? <String, String>{};

  final Map<String, String> _values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = _values[key];
    return Success(
      value == null
          ? null
          : AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.utc(2026, 10, 5),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    _values[setting.key] = setting.value;
    return const Success(null);
  }
}

/// إعدادات تقرأ بنجاح لكنها تفشل في كل قراءة — لاختبار أن فشل الإعدادات يوقف الإرسال.
final class _FailingSettings implements SettingsRepository {
  @override
  Future<Result<AppSetting?>> find(String key) async => const Failure(
        AppFailure(code: 'settings_unavailable', message: 'db down'),
      );

  @override
  Future<Result<void>> save(AppSetting setting) async => const Success(null);
}

void main() {
  test('strict render succeeds when all placeholders resolved', () {
    final r = OutboundTemplateRenderer.renderStrict(
      template: 'رقم الكرت: {serial}\nالرمز: {code}',
      values: {'serial': '111', 'code': '222'},
    );
    expect(r, isA<Success<String>>());
    expect((r as Success<String>).value, contains('111'));
  });

  test('strict render supports Arabic placeholder names', () {
    final r = OutboundTemplateRenderer.renderStrict(
      template: 'كرتك من {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}',
      values: {
        'اسم_المحفظة': 'شبكة كيان',
        'الفئة': '100 ر.ي',
        'الرقم': '111',
        'الرمز': '222',
      },
    );
    expect(r, isA<Success<String>>());
    expect((r as Success<String>).value, 'كرتك من شبكة كيان\n100 ر.ي\n111\n222');
  });

  test('strict render fails on unresolved placeholder', () {
    final r = OutboundTemplateRenderer.renderStrict(
      template: 'كرت {serial_number} والرمز {code}',
      values: {'serial': '111', 'code': '222'},
    );
    expect(r, isA<Failure<String>>());
    final err = (r as Failure<String>).error;
    expect(err.code, 'outbound_unresolved_placeholder');
    expect(err.message, contains('serial_number'));
  });

  test('unresolvedPlaceholders lists remaining tokens', () {
    final left = OutboundTemplateRenderer.unresolvedPlaceholders(
      'hello {a} and {b} and {a}',
    );
    expect(left.toSet(), {'a', 'b'});
  });

  test('voucher delivery resolves the saved network name', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings(<String, String>{
        ...OutboundTemplateCatalog.initialBodies(),
        SettingKeys.networkName: 'شبكة الاختبار',
      }),
    ).renderVoucherDelivery(serialNumber: '111', secretCode: '222');

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, contains('شبكة الاختبار'));
    expect((result as Success<String>).value, isNot(contains('NET')));
  });

  test('voucher delivery resolves Arabic aliases from existing card data', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings(<String, String>{
        SettingKeys.voucherDeliverySmsTemplate:
            'من {اسم_المحفظة} فئة {الفئة} رقم {الرقم} رمز {الرمز}',
        SettingKeys.networkName: 'شبكة الاختبار',
      }),
    ).renderVoucherDelivery(
      serialNumber: '111',
      secretCode: '222',
      cardValue: '100 ر.ي',
    );

    expect(result, isA<Success<String>>());
    expect(
      (result as Success<String>).value,
      'من شبكة الاختبار فئة 100 ر.ي رقم 111 رمز 222',
    );
  });

  test('falls back to the card secret when the card has no serial', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings(<String, String>{
        SettingKeys.voucherDeliverySmsTemplate: 'هوية {المستخدم}',
      }),
    ).renderVoucherDelivery(serialNumber: '   ', secretCode: 'PIN-9');

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'هوية PIN-9');
  });

  test('maps المستخدم to the card serial number, never an operator name', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings(<String, String>{
        SettingKeys.voucherDeliverySmsTemplate: 'هوية {المستخدم} / {user}',
      }),
    ).renderVoucherDelivery(serialNumber: 'SERIAL-9', secretCode: 'PIN-9');

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'هوية SERIAL-9 / SERIAL-9');
  });

  group('no template in settings → no send', () {
    test('a missing template setting is refused (never the built-in fallback)',
        () async {
      final result = await OutboundTemplateRenderer(settings: _Settings())
          .renderVoucherDelivery(serialNumber: '111', secretCode: '222');
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_missing',
      );
    });

    test('an empty template setting is refused', () async {
      final result = await OutboundTemplateRenderer(
        settings: _Settings(<String, String>{
          SettingKeys.voucherDeliverySmsTemplate: '   ',
        }),
      ).renderVoucherDelivery(serialNumber: '111', secretCode: '222');
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_missing',
      );
    });

    test('a settings read failure stops the send', () async {
      final result = await OutboundTemplateRenderer(settings: _FailingSettings())
          .renderVoucherDelivery(serialNumber: '111', secretCode: '222');
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_settings_read_failed',
      );
    });

    test('no settings repository at all stops the send', () async {
      final result = await const OutboundTemplateRenderer()
          .renderVoucherDelivery(serialNumber: '111', secretCode: '222');
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_settings_unavailable',
      );
    });

    test('an unregistered template key is refused', () async {
      final result = await OutboundTemplateRenderer(settings: _Settings())
          .renderRegistered(key: 'not_a_registered_template', values: const {});
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_unregistered',
      );
    });

    test('an unknown placeholder inside the stored template is refused',
        () async {
      final result = await OutboundTemplateRenderer(
        settings: _Settings(<String, String>{
          SettingKeys.voucherDeliverySmsTemplate: 'كرت {serial} و {mystery}',
        }),
      ).renderVoucherDelivery(serialNumber: '111', secretCode: '222');
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_unknown_variable',
      );
    });

    test('an unresolved % placeholder is refused', () async {
      // متغيرات مسموحة في العقد لكن مسار الإرسال لم يمرّر لها قيمًا:
      // يجب أن يُرفض الإرسال لا أن تصل `%serial` حرفيًا للعميل.
      final result = await OutboundTemplateRenderer(
        settings: _Settings(<String, String>{
          SettingKeys.voucherDeliverySmsTemplate: 'كرت %serial و %CARD_VALUE',
        }),
      ).renderRegistered(
        key: SettingKeys.voucherDeliverySmsTemplate,
        values: const <String, String>{'code': '987654'},
      );
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_unresolved_placeholder',
      );
    });

    test('a caller that omits a required value is refused', () async {
      final result = await OutboundTemplateRenderer(
        settings: _Settings(<String, String>{
          SettingKeys.voucherDeliverySmsTemplate: 'كود الكرت {serial} والرمز {code}',
        }),
      ).renderRegistered(
        key: SettingKeys.voucherDeliverySmsTemplate,
        values: const <String, String>{'serial': '111'},
      );
      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).error.code,
        'outbound_template_missing_value',
      );
    });
  });

  group('placeholder detection covers both syntaxes', () {
    test('% tokens are listed as unresolved', () {
      final left = OutboundTemplateRenderer.unresolvedPlaceholders(
        'hello {a} and %beta',
      );
      expect(left.toSet(), {'a', 'beta'});
    });

    test('% tokens with a one-character name are detected', () {
      expect(
        OutboundTemplateRenderer.unresolvedPlaceholders('hello %x'),
        ['x'],
      );
    });

    test('a trailing percent without an identifier is not a placeholder', () {
      final left = OutboundTemplateRenderer.unresolvedPlaceholders(
        'خصم 50% على الكروت',
      );
      expect(left, isEmpty);
    });
  });
}
