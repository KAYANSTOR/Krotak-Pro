import 'dart:convert';

import 'customer_file_currency.dart';

/// عملة الحساب الدائمة. لا تعيد كتابة الدفتر ولا تحوّل الحركات التاريخية.
final class CustomerAccountCurrency {
  const CustomerAccountCurrency._();

  static const defaultCode = CustomerFileCurrency.defaultCode;

  static Map<String, String> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        final id = key.toString().trim();
        final code = normalize(value?.toString());
        if (id.isEmpty || code == null) return;
        out[id] = code;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// يرفض الرمز غير المعروف. الريال اليمني يبقى الافتراضي عند المسح.
  static String? normalize(String? raw) {
    final code = raw?.trim().toUpperCase() ?? '';
    if (code.isEmpty || code == defaultCode) return null;
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return null;
    return code;
  }

  static String? lookup(String? raw, String customerId) {
    final id = customerId.trim();
    if (id.isEmpty) return null;
    return decodeMap(raw)[id];
  }

  static String encodeMap(
    String? raw, {
    required String customerId,
    required String? currencyCode,
  }) {
    final next = Map<String, String>.from(decodeMap(raw));
    final id = customerId.trim();
    final code = normalize(currencyCode);
    if (id.isEmpty) return jsonEncode(next);
    if (code == null) {
      next.remove(id);
    } else {
      next[id] = code;
    }
    return jsonEncode(next);
  }

  /// العملة المخزّنة إن كانت ضمن المتاح، وإلا الريال اليمني.
  static String preferred(
    String? raw,
    String customerId,
    Iterable<String> available,
  ) {
    final stored = lookup(raw, customerId);
    return CustomerFileCurrency.keepOrDefault(
      stored ?? defaultCode,
      available,
    );
  }

  /// يُبقي العملة الدائمة ظاهرة حتى لو لم تُسجَّل بها حركة بعد.
  static List<String> withPreferred(
    Iterable<String> available,
    String? preferredCode,
  ) {
    final codes = available.toList();
    final code = normalize(preferredCode) ?? defaultCode;
    if (!codes.contains(code)) codes.add(code);
    return codes;
  }
}
