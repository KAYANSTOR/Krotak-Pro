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
    String cardValue = 'غير محدد',
    String? networkName,
    String currency = 'ر.ي',
  }) {
    return _renderVoucherDelivery(
      serialNumber: serialNumber,
      secretCode: secretCode,
      cardValue: cardValue,
      networkName: networkName,
      currency: currency,
    );
  }

  Future<Result<String>> _renderVoucherDelivery({
    required String serialNumber,
    required String secretCode,
    required String cardValue,
    required String? networkName,
    required String currency,
  }) async {
    final serial = serialNumber.trim();
    final secret = secretCode.trim();
    var resolvedNetworkName = networkName?.trim() ?? '';
    if (resolvedNetworkName.isEmpty && settings != null) {
      final stored = await settings!.find(SettingKeys.networkName);
      if (stored is Success<AppSetting?>) {
        resolvedNetworkName = stored.value?.value.trim() ?? '';
      }
    }
    final values = <String, String>{
      'serial': serial,
      'serial_number': serial,
      'code': secret,
      'secret': secret,
      'CARD_CODE': serial,
      'CARD_SERIAL': serial,
      'CARD_VALUE': cardValue.trim().isEmpty ? 'غير محدد' : cardValue.trim(),
      'NETWORK_NAME': resolvedNetworkName.isEmpty
          ? SettingDefaults.networkName
          : resolvedNetworkName,
      'CURRENCY': currency,
    };
    final fallback = SettingDefaults.voucherDeliverySmsTemplate;
    return renderFromSettings(
      key: SettingKeys.voucherDeliverySmsTemplate,
      fallback: fallback,
      values: values,
    );
  }
}
