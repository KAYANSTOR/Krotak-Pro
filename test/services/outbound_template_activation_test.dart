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
          : AppSetting(key: key, value: value, updatedAt: DateTime.utc(2026, 10, 3)),
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
  const key = 'voucher_delivery_sms_template';
  const fallback = 'الافتراضي {serial}';

  late _MemSettings settings;
  late OutboundTemplateActivation activation;

  setUp(() {
    settings = _MemSettings()..values[key] = 'نص النظام {serial}';
    activation = OutboundTemplateActivation(settings: settings, clock: _Clock());
  });

  test('activate writes the custom body under the system key and keeps the original', () async {
    final r = await activation.activate(
      systemKey: key,
      customId: 'tpl-1',
      customBody: 'نص مخصص {serial}',
      systemFallback: fallback,
    );
    expect(r, isA<Success<void>>());
    expect(settings.values[key], 'نص مخصص {serial}');
    expect(await activation.originalBody(key), 'نص النظام {serial}');
    expect(await activation.loadActive(), {key: 'tpl-1'});
  });

  test('switching between two custom templates keeps the first original', () async {
    await activation.activate(systemKey: key, customId: 'a', customBody: 'A', systemFallback: fallback);
    await activation.activate(systemKey: key, customId: 'b', customBody: 'B', systemFallback: fallback);
    expect(settings.values[key], 'B');
    expect(await activation.originalBody(key), 'نص النظام {serial}');
    expect(await activation.loadActive(), {key: 'b'});
  });

  test('revert restores the original system body and clears the override', () async {
    await activation.activate(systemKey: key, customId: 'a', customBody: 'A', systemFallback: fallback);
    final r = await activation.revert(systemKey: key, systemFallback: fallback);
    expect(r, isA<Success<void>>());
    expect(settings.values[key], 'نص النظام {serial}');
    expect(await activation.loadActive(), isEmpty);
  });

  test('revert is a no-op when nothing is overridden', () async {
    final r = await activation.revert(systemKey: key, systemFallback: fallback);
    expect(r, isA<Success<void>>());
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('editing the system template while overridden only changes the stored original', () async {
    await activation.activate(systemKey: key, customId: 'a', customBody: 'A', systemFallback: fallback);
    await activation.saveSystemBody(key, 'نظام معدّل');
    expect(settings.values[key], 'A');
    await activation.revert(systemKey: key, systemFallback: fallback);
    expect(settings.values[key], 'نظام معدّل');
  });

  test('editing the system template when not overridden writes it directly', () async {
    await activation.saveSystemBody(key, 'جديد');
    expect(settings.values[key], 'جديد');
  });

  test('syncActiveBody updates the sent text only for the active custom template', () async {
    await activation.activate(systemKey: key, customId: 'a', customBody: 'A', systemFallback: fallback);
    await activation.syncActiveBody(key, 'other', 'X');
    expect(settings.values[key], 'A');
    await activation.syncActiveBody(key, 'a', 'A2');
    expect(settings.values[key], 'A2');
  });

  test('activate rejects an empty body', () async {
    final r = await activation.activate(systemKey: key, customId: 'a', customBody: '  ', systemFallback: fallback);
    expect(r, isA<Failure<void>>());
    expect(settings.values[key], 'نص النظام {serial}');
  });

  test('a corrupt registry is treated as empty', () async {
    settings.values[SettingKeys.activeOutboundTemplates] = '{not json';
    expect(await activation.loadActive(), isEmpty);
  });
}
