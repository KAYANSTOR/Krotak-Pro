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
  ];

  /// النص الفارغ يعود للافتراضي حتى لا يُحفظ قالب بلا رسالة.
  static String normalize(String? raw, {required String fallback}) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? fallback.trim() : trimmed;
  }

  /// قالب العرض إن وُجد، وإلا القالب العام، وإلا الافتراضي.
  static String resolve({
    required String? perOffer,
    required String? global,
    required String fallback,
  }) {
    final specific = perOffer?.trim() ?? '';
    if (specific.isNotEmpty) return specific;
    return normalize(global, fallback: fallback);
  }

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
