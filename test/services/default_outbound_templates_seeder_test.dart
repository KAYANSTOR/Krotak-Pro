import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/default_outbound_templates_seeder.dart';

final class _MemSettings implements SettingsRepository {
  _MemSettings([Map<String, String>? values])
      : values = values ?? <String, String>{};

  final Map<String, String> values;

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final value = values[key];
    return Success(
      value == null
          ? null
          : AppSetting(
              key: key,
              value: value,
              updatedAt: DateTime.utc(2026, 9, 22),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    values[setting.key] = setting.value;
    return const Success(null);
  }
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 22);
}

Future<Result<void>> _seed(_MemSettings settings) =>
    DefaultOutboundTemplatesSeeder(settings: settings, clock: _FixedClock())
        .seedIfNeeded();

void main() {
  test('migrates the released POS customer template so category is included', () async {
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate:
          'شبكة {NETWORK_NAME}\nالفئة: {CARD_VALUE} {CURRENCY}\n{cards}',
    });

    final result = await _seed(settings);

    expect(result, isA<Success<void>>());
    expect(
      settings.values[SettingKeys.posCustomerCardDeliveryTemplate],
      'شبكة {NETWORK_NAME}\nالفئة: {category}\n{cards}',
    );
  });

  test('migrates the legacy POS customer template without category', () async {
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate:
          'شبكة {NETWORK_NAME}\n{cards}',
    });

    await _seed(settings);
    expect(
      settings.values[SettingKeys.posCustomerCardDeliveryTemplate],
      'شبكة {NETWORK_NAME}\nالفئة: {category}\n{cards}',
    );
  });

  test('does not overwrite an operator-customized POS customer template', () async {
    const custom = 'شبكة خاصة {NETWORK_NAME}\nللعميل {CUSTOMER_PHONE}\n{cards}';
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate: custom,
    });

    await _seed(settings);
    expect(settings.values[SettingKeys.posCustomerCardDeliveryTemplate], custom);
  });

  test('migrates a legacy active custom template and restores its system body', () async {
    const id = 'legacy-1';
    const customBody = 'قالب قديم للعميل {serial}';
    const systemBody = 'نص النظام الأصلي {serial}';
    final systemKey = SettingKeys.voucherDeliverySmsTemplate;
    final settings = _MemSettings(<String, String>{
      SettingKeys.customOutboundTemplates: jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': id,
          'title': 'قالب مخصص قديم',
          'tab': 0,
          'target': systemKey,
          'body': customBody,
        },
      ]),
      SettingKeys.activeOutboundTemplates:
          jsonEncode(<String, String>{systemKey: id}),
      systemKey: customBody,
      SettingKeys.outboundSystemOriginal(systemKey): systemBody,
    });

    final result = await _seed(settings);

    expect(result, isA<Success<void>>());
    expect(settings.values[SettingKeys.customOutboundBody(id)], customBody);
    expect(settings.values[systemKey], systemBody);
    expect(settings.values[SettingKeys.outboundSystemOriginal(systemKey)], '');
    expect(jsonDecode(settings.values[SettingKeys.activeOutboundTemplates]!),
        {systemKey: id});
  });

  test('migrates custom body from the old custom:<id> setting', () async {
    const id = 'legacy-2';
    const body = 'قالب مخصص محفوظ بالمفتاح القديم';
    final settings = _MemSettings(<String, String>{
      SettingKeys.customOutboundTemplates: jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'id': id, 'title': 'قديم', 'tab': 0},
      ]),
      SettingKeys.legacyCustomOutboundBody(id): body,
    });

    await _seed(settings);
    expect(settings.values[SettingKeys.customOutboundBody(id)], body);
  });

  test('re-running migration preserves new-format body and operator system edits', () async {
    const id = 'legacy-3';
    final systemKey = SettingKeys.voucherDeliverySmsTemplate;
    final settings = _MemSettings(<String, String>{
      SettingKeys.customOutboundTemplates: jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'id': id, 'title': 'قديم', 'tab': 0, 'body': 'نص قديم'},
      ]),
      SettingKeys.activeOutboundTemplates:
          jsonEncode(<String, String>{systemKey: id}),
      SettingKeys.outboundSystemOriginal(systemKey): 'الأصل',
      systemKey: 'نص قديم',
    });

    await _seed(settings);
    settings.values[SettingKeys.customOutboundBody(id)] = 'تعديل القالب';
    settings.values[systemKey] = 'تعديل المشغل لقالب النظام';
    await _seed(settings);

    expect(settings.values[SettingKeys.customOutboundBody(id)], 'تعديل القالب');
    expect(settings.values[systemKey], 'تعديل المشغل لقالب النظام');
  });
}
