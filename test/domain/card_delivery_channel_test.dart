import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/outbound_template_catalog.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

final class _Settings implements SettingsRepository {
  _Settings(this._values);
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
              updatedAt: DateTime.utc(2026, 10, 9),
            ),
    );
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    _values[setting.key] = setting.value;
    return const Success(null);
  }
}

void main() {
  test('cash channel uses the cash card template, not the legacy body', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings({
        ...OutboundTemplateCatalog.initialBodies(),
        SettingKeys.voucherDeliverySmsTemplate: 'LEGACY {serial}',
        SettingKeys.cardDeliveryCashTemplate:
            'نقدي {اسم_المحفظة} {الفئة} {الرقم} {الرمز}',
        SettingKeys.networkName: 'كيان',
      }),
    ).renderVoucherDelivery(
      serialNumber: '111',
      secretCode: '222',
      cardValue: '100',
      channel: CardDeliveryChannel.cash,
    );
    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'نقدي كيان 100 111 222');
  });

  test('missing typed template falls back to the legacy voucher template', () async {
    final result = await OutboundTemplateRenderer(
      settings: _Settings({
        SettingKeys.voucherDeliverySmsTemplate: 'قديم {serial}/{code}',
        SettingKeys.networkName: 'كيان',
      }),
    ).renderVoucherDelivery(
      serialNumber: '111',
      secretCode: '222',
      channel: CardDeliveryChannel.gift,
    );
    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'قديم 111/222');
  });
}
