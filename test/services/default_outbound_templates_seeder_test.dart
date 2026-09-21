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

void main() {
  test('migrates the released POS customer template so category is included', () async {
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate:
          'شبكة {NETWORK_NAME}\nالفئة: {CARD_VALUE} {CURRENCY}\n{cards}',
    });

    final result = await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: _FixedClock(),
    ).seedIfNeeded();

    expect(result, isA<Success<void>>());
    expect(
      settings.values[SettingKeys.posCustomerCardDeliveryTemplate],
      'شبكة {NETWORK_NAME}\nالفئة: {category}\n{cards}',
    );
  });

  test('migrates the legacy POS customer template that had no category line', () async {
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate:
          'شبكة {NETWORK_NAME}\n{cards}',
    });

    await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: _FixedClock(),
    ).seedIfNeeded();

    expect(
      settings.values[SettingKeys.posCustomerCardDeliveryTemplate],
      'شبكة {NETWORK_NAME}\nالفئة: {category}\n{cards}',
    );
  });

  test('does not overwrite an operator-customized POS customer template', () async {
    const custom =
        'شبكة خاصة {NETWORK_NAME}\nللعميل {CUSTOMER_PHONE}\n{cards}';
    final settings = _MemSettings(<String, String>{
      SettingKeys.posCustomerCardDeliveryTemplate: custom,
    });

    await DefaultOutboundTemplatesSeeder(
      settings: settings,
      clock: _FixedClock(),
    ).seedIfNeeded();

    expect(
      settings.values[SettingKeys.posCustomerCardDeliveryTemplate],
      custom,
    );
  });
}
