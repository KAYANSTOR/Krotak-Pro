import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/entities/setting.dart';
import 'package:net_app/domain/repositories/repositories.dart';
import 'package:net_app/domain/services/outbound_template_renderer.dart';

final class _Settings implements SettingsRepository {
  @override
  Future<Result<AppSetting?>> find(String key) async => Success(
        key == SettingKeys.networkName
            ? AppSetting(
                key: key,
                value: 'شبكة الاختبار',
                updatedAt: DateTime.utc(2026, 10, 5),
              )
            : null,
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
    final result = await OutboundTemplateRenderer(settings: _Settings())
        .renderVoucherDelivery(serialNumber: '111', secretCode: '222');

    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, contains('شبكة الاختبار'));
    expect((result as Success<String>).value, isNot(contains('NET')));
  });
}
