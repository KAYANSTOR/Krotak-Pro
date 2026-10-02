import 'dart:convert';

/// نص رسالة مكافأة العرض: تطبيع وحفظ المتغيرات المعروفة.
class PromotionRewardTemplate {
  const PromotionRewardTemplate._();

  static const knownPlaceholders = <String>[
    'title',
    'serial',
    'secret',
    'code',
    'amount',
    'promotion_name',
    'reward_value',
    'customer_name',
  ];

  /// النص الفارغ يعود للافتراضي حتى لا يُحفظ قالب بلا رسالة.
  static String normalize(String? raw, {required String fallback}) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? fallback.trim() : trimmed;
  }

  /// العميل داخل العرض، ثم قالب العرض، ثم قالب العميل العام، ثم العام، ثم الافتراضي.
  static String resolve({
    String? perCustomer,
    required String? perOffer,
    String? perCustomerGlobal,
    required String? global,
    required String fallback,
  }) {
    final customer = perCustomer?.trim() ?? '';
    if (customer.isNotEmpty) return customer;
    final specific = perOffer?.trim() ?? '';
    if (specific.isNotEmpty) return specific;
    final generalCustomer = perCustomerGlobal?.trim() ?? '';
    if (generalCustomer.isNotEmpty) return generalCustomer;
    return normalize(global, fallback: fallback);
  }

  static String customerKey(String promotionId, String customerId) =>
      '${promotionId.trim()}|${customerId.trim()}';

  static String? lookupCustomer(
    String? raw,
    String promotionId,
    String customerId,
  ) =>
      lookup(raw, customerKey(promotionId, customerId));

  static String? lookupGlobalCustomer(String? raw, String customerId) =>
      lookup(raw, customerId.trim());

  /// النص الفارغ يحذف قالب العميل العام ويعيده إلى قالب العرض أو العام.
  static String encodeGlobalCustomerMap(
    String? raw, {
    required String customerId,
    required String? body,
  }) =>
      encodeMap(raw, promotionId: customerId.trim(), body: body);

  /// النص الفارغ يحذف تخصيص العميل ويعيد العرض إلى قالب العرض/العام.
  static String encodeCustomerMap(
    String? raw, {
    required String promotionId,
    required String customerId,
    required String? body,
  }) =>
      encodeMap(
        raw,
        promotionId: customerKey(promotionId, customerId),
        body: body,
      );

  static Map<String, String> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        final id = key.toString().trim();
        final body = value?.toString().trim() ?? '';
        if (id.isEmpty || body.isEmpty) return;
        out[id] = body;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String? lookup(String? raw, String promotionId) {
    final body = decodeMap(raw)[promotionId];
    if (body == null || body.trim().isEmpty) return null;
    return body.trim();
  }

  /// يحدّث خريطة القوالب. النص الفارغ يحذف تخصيص العرض ويعود للقالب العام.
  static String encodeMap(
    String? raw, {
    required String promotionId,
    required String? body,
  }) {
    final next = Map<String, String>.from(decodeMap(raw));
    final trimmed = body?.trim() ?? '';
    if (trimmed.isEmpty) {
      next.remove(promotionId);
    } else {
      next[promotionId] = trimmed;
    }
    return jsonEncode(next);
  }

  /// المتغيرات المكتوبة `{name}` وغير المعروفة لصرف المكافأة.
  static List<String> unknownPlaceholders(String body) {
    final found = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'\{([^{}]+)\}').allMatches(body)) {
      final name = match.group(1)!.trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      if (!knownPlaceholders.contains(name)) found.add(name);
    }
    return found;
  }
}
