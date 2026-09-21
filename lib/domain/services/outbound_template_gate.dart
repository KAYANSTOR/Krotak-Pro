import 'dart:convert';

import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// بوابة إرسال الرسائل الصادرة.
///
/// أي قالب مُدرَج في [SettingKeys.outboundTemplatesDisabled] لا يُحمَّل نصه
/// ولا يُرسل — حتى لو وُجد fallback في الكود.
final class OutboundTemplateGate {
  const OutboundTemplateGate(this.settings);

  final SettingsRepository settings;

  static const disabledCode = 'outbound_template_disabled';

  Future<bool> isEnabled(String templateKey) async {
    final key = templateKey.trim();
    if (key.isEmpty) return true;
    final found = await settings.find(SettingKeys.outboundTemplatesDisabled);
    if (found is Failure<AppSetting?>) return true;
    final raw = (found as Success<AppSetting?>).value?.value;
    if (raw == null || raw.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return true;
      return !decoded.map((e) => '$e'.trim()).contains(key);
    } on FormatException {
      return true;
    }
  }

  /// نص القالب أو `null` إذا كان متوقفاً.
  Future<Result<String?>> resolveBody({
    required String key,
    required String fallback,
  }) async {
    if (!await isEnabled(key)) {
      return const Success(null);
    }
    final found = await settings.find(key);
    if (found is Failure<AppSetting?>) return Failure(found.error);
    final value = (found as Success<AppSetting?>).value?.value.trim();
    if (value == null || value.isEmpty) {
      return Success(fallback);
    }
    return Success(value);
  }

  /// مثل [resolveBody] لكن يفشل بكود ثابت عند الإيقاف — لمسارات Result.
  Future<Result<String>> requireBody({
    required String key,
    required String fallback,
  }) async {
    final resolved = await resolveBody(key: key, fallback: fallback);
    if (resolved is Failure<String?>) {
      return Failure(resolved.error);
    }
    final body = (resolved as Success<String?>).value;
    if (body == null) {
      return const Failure(
        AppFailure(
          code: disabledCode,
          message: 'قالب الرسالة متوقف من الإعدادات — لن يُرسل',
        ),
      );
    }
    return Success(body);
  }

  /// يطبّق المتغيرات على القالب؛ يعيد `null` إذا كان متوقفاً.
  Future<Result<String?>> render({
    required String key,
    required String fallback,
    Map<String, String> values = const {},
  }) async {
    final resolved = await resolveBody(key: key, fallback: fallback);
    if (resolved is Failure<String?>) return Failure(resolved.error);
    final body = (resolved as Success<String?>).value;
    if (body == null) return const Success(null);
    return Success(applyVars(body, values));
  }

  static String applyVars(String template, Map<String, String> values) {
    var output = template;
    for (final e in values.entries) {
      output = output.replaceAll('{${e.key}}', e.value);
      output = output.replaceAll('%${e.key}', e.value);
    }
    return output.trim();
  }

  /// نص تسليم الكرت من قالب النظام أو الـfallback؛ `null` إذا أُوقف القالب.
  Future<String?> voucherBody({
    required String serialNumber,
    required String secretCode,
  }) async {
    final serial = serialNumber.trim();
    final secret = secretCode.trim();
    final fallback = secret.isEmpty
        ? 'بطاقة الإنترنت\nالرقم: $serial'
        : 'بطاقة الإنترنت\nالرقم: $serial\nالرمز: $secret';
    final rendered = await render(
      key: SettingKeys.voucherDeliverySmsTemplate,
      fallback: fallback,
      values: {
        'serial': serial,
        'code': secret,
        'secret': secret,
        'CARD_CODE': serial,
        'SECRET': secret,
        'CODE': secret,
      },
    );
    if (rendered is Failure<String?>) return null;
    return (rendered as Success<String?>).value;
  }
}
