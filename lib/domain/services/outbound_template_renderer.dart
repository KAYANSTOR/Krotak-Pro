import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// Central outbound SMS template render + strict unresolved-placeholder guard.
///
/// Any `{token}` left after substitution must **not** be sent to customers.
final class OutboundTemplateRenderer {
  const OutboundTemplateRenderer({this.settings});

  final SettingsRepository? settings;

  /// Matches `{name}` tokens (letters, digits, underscore). Ignores empty `{}`.
  static final RegExp placeholderPattern = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');

  /// Returns remaining placeholder names after known values are applied.
  static List<String> unresolvedPlaceholders(String body) {
    return placeholderPattern
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet()
        .toList(growable: false);
  }

  /// Apply [values] (keys without braces). Supports `{key}` and `%key`.
  static String substitute(String template, Map<String, String> values) {
    var result = template;
    for (final e in values.entries) {
      result = result.replaceAll('{${e.key}}', e.value);
      result = result.replaceAll('%${e.key}', e.value);
    }
    return result;
  }

  /// Strict render: fails if any `{token}` remains.
  static Result<String> renderStrict({
    required String template,
    required Map<String, String> values,
  }) {
    final body = substitute(template, values).trim();
    if (body.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'outbound_template_empty',
          message: 'نص القالب الناتج فارغ — لن يُرسل',
        ),
      );
    }
    final left = unresolvedPlaceholders(body);
    if (left.isNotEmpty) {
      return Failure(
        AppFailure(
          code: 'outbound_unresolved_placeholder',
          message:
              'رفض الإرسال: متغيرات غير مستبدلة في القالب: ${left.map((e) => '{$e}').join(', ')}',
        ),
      );
    }
    return Success(body);
  }

  /// Load setting [key] or [fallback], then strict-render.
  Future<Result<String>> renderFromSettings({
    required String key,
    required String fallback,
    required Map<String, String> values,
  }) async {
    var template = fallback;
    final repo = settings;
    if (repo != null) {
      final found = await repo.find(key);
      if (found is Success<AppSetting?>) {
        final v = found.value?.value.trim();
        if (v != null && v.isNotEmpty) template = v;
      }
    }
    return renderStrict(template: template, values: values);
  }

  /// Voucher / card delivery body (serial + optional PIN).
  Future<Result<String>> renderVoucherDelivery({
    required String serialNumber,
    required String secretCode,
  }) {
    final serial = serialNumber.trim();
    final secret = secretCode.trim();
    final values = <String, String>{
      'serial': serial,
      'serial_number': serial,
      'code': secret,
      'secret': secret,
      'CARD_CODE': secret,
      'CARD_SERIAL': serial,
    };
    final fallback = secret.isEmpty
        ? 'بطاقة الإنترنت\nالرقم: {serial}'
        : SettingDefaults.voucherDeliverySmsTemplate;
    return renderFromSettings(
      key: SettingKeys.voucherDeliverySmsTemplate,
      fallback: fallback,
      values: values,
    );
  }
}
