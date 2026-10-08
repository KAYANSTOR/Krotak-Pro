import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/outbound_template_activation.dart';

final class _MemSettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    return Success(
      value == null
          ? null
          : AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.utc(2026, 10, 3),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 10, 3);
}

void main() {
  const key = SettingKeys.voucherDeliverySmsTemplate;

  late _MemSettings settings;
  late OutboundTemplateActivation activation;

  setUp(() {
    settings = _MemSettings()
      ..values[key] = 'نص النظام {serial}'
      // نص القالب المخصّص له مصدر واحد: مفتاح custom_outbound_body.
      ..values[SettingKeys.customOutboundBody('a')] = 'نص مخصص أ {serial}'
      ..values[SettingKeys.customOutboundBody('b')] = 'نص مخصص ب {serial}';
    activation = OutboundTemplateActivation(settings: settings, clock: _Clock());
  });

  test('activate records the decision without touching the system template',
      () async {
    final r = await activation.activate(systemKey: key, customId: 'a');
    expect(r, isA<Success<void>>());
    expect(await activation.loadActive(), {key: 'a'});
    expect(
      settings.values[key],
      'نص النظام {serial}',
      reason: 'قالب النظام لا يُكتب فوقه أبدًا — لا مصدران متنافسان',
    );
  });

  test('switching between two custom templates keeps the system body intact',
      () async {
    await activation.activate(systemKey: key, customId: 'a');
    await activation.activate(systemKey: key, customId: 'b');
    expect(await activation.loadActive(), {key: 'b'});
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('revert clears the override and the system body was never changed',
      () async {
    await activation.activate(systemKey: key, customId: 'a');
    final r = await activation.revert(systemKey: key);
    expect(r, isA<Success<void>>());
    expect(await activation.loadActive(), isEmpty);
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('revert is a no-op when nothing is overridden', () async {
    final r = await activation.revert(systemKey: key);
    expect(r, isA<Success<void>>());
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('activate refuses a custom template with no stored body', () async {
    final r = await activation.activate(systemKey: key, customId: 'missing');
    expect(r, isA<Failure<void>>());
    expect(
      (r as Failure<void>).error.code,
      'template_empty',
      reason: 'لا تُكتب خريطة تفعيل تشير إلى قالب غير موجود',
    );
    expect(await activation.loadActive(), isEmpty);
  });

  test('activate refuses a custom template whose body is blank', () async {
    settings.values[SettingKeys.customOutboundBody('blank')] = '   ';
    final r = await activation.activate(systemKey: key, customId: 'blank');
    expect(r, isA<Failure<void>>());
    expect(await activation.loadActive(), isEmpty);
  });

  test('editing the custom body is the only write that changes what is sent',
      () async {
    await activation.activate(systemKey: key, customId: 'a');
    settings.values[SettingKeys.customOutboundBody('a')] = 'نص معدّل {serial}';
    expect(await activation.loadActive(), {key: 'a'});
    expect(settings.values[SettingKeys.customOutboundBody('a')],
        'نص معدّل {serial}');
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('clear drops every override at once', () async {
    await activation.activate(systemKey: key, customId: 'a');
    final r = await activation.clear();
    expect(r, isA<Success<void>>());
    expect(await activation.loadActive(), isEmpty);
  });

  test('a corrupt registry is treated as empty', () async {
    settings.values[SettingKeys.activeOutboundTemplates] = '{not json';
    expect(await activation.loadActive(), isEmpty);
  });
}
