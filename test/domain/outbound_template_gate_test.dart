import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/outbound_template_gate.dart';

final class _MemSettings implements SettingsRepository {
  final Map<String, String> data = {};
  final _now = DateTime.utc(2026, 9, 21);

  @override
  Future<Result<AppSetting?>> find(String key) async {
    final v = data[key];
    if (v == null) return const Success(null);
    return Success(AppSetting(key: key, value: v, updatedAt: _now));
  }

  @override
  Future<Result<void>> save(AppSetting setting) async {
    data[setting.key] = setting.value;
    return const Success(null);
  }
}

void main() {
  test('enabled by default when no disabled list', () async {
    final s = _MemSettings();
    final g = OutboundTemplateGate(s);
    expect(await g.isEnabled(SettingKeys.voucherDeliverySmsTemplate), isTrue);
    final body = await g.resolveBody(
      key: SettingKeys.voucherDeliverySmsTemplate,
      fallback: 'fallback',
    );
    expect((body as Success<String?>).value, 'fallback');
  });

  test('disabled key returns null body and requireBody fails', () async {
    final s = _MemSettings();
    s.data[SettingKeys.outboundTemplatesDisabled] = jsonEncode([
      SettingKeys.salafniAcceptedTemplate,
    ]);
    final g = OutboundTemplateGate(s);
    expect(await g.isEnabled(SettingKeys.salafniAcceptedTemplate), isFalse);
    expect(await g.isEnabled(SettingKeys.salafniRejectedTemplate), isTrue);

    final resolved = await g.resolveBody(
      key: SettingKeys.salafniAcceptedTemplate,
      fallback: 'x',
    );
    expect((resolved as Success<String?>).value, isNull);

    final required = await g.requireBody(
      key: SettingKeys.salafniAcceptedTemplate,
      fallback: 'x',
    );
    expect(required, isA<Failure<String>>());
    expect(
      (required as Failure<String>).error.code,
      OutboundTemplateGate.disabledCode,
    );
  });

  test('render applies variables when enabled', () async {
    final s = _MemSettings();
    s.data[SettingKeys.posBalanceResponseTemplate] = 'رصيد {pos}: {balance}';
    final g = OutboundTemplateGate(s);
    final r = await g.render(
      key: SettingKeys.posBalanceResponseTemplate,
      fallback: '',
      values: {'pos': 'الأمل', 'balance': '10'},
    );
    expect((r as Success<String?>).value, 'رصيد الأمل: 10');
  });
}
