/// نص رسالة مكافأة العرض: تطبيع وحفظ المتغيرات المعروفة.
class PromotionRewardTemplate {
  const PromotionRewardTemplate._();

  static const knownPlaceholders = <String>[
    'title',
    'serial',
    'secret',
    'code',
    'promotion_name',
    'reward_value',
  ];

  /// النص الفارغ يعود للافتراضي حتى لا يُحفظ قالب بلا رسالة.
  static String normalize(String? raw, {required String fallback}) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? fallback.trim() : trimmed;
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
