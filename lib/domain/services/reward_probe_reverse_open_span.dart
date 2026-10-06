import 'promotion_reward_template.dart';

/// عكس مقطع طابور المعاينة بين موضعين يختارهما المشغّل.
/// المقطع لا يُشترط أن يبدأ من الكرت الظاهر؛ الكرت الظاهر يحدد الطابور ويجب أن يقع داخل المقطع.
/// الكروت خارج المقطع تبقى في أماكنها. الحجوزات وموعد الانتهاء يبقيان.
class RewardProbeReverseOpenSpan {
  const RewardProbeReverseOpenSpan._();

  static String reverseOpenSpan(
    String? raw, {
    required String cardId,
    required int startPosition,
    required int endPosition,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || startPosition < 1 || endPosition < 1) {
      return raw ?? '{}';
    }
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _reverseHold(raw, cross, wanted, startPosition, endPosition);
    }
    final map = PromotionRewardTemplate.decodeHoldMap(raw);
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final categoryId = key.split('|customer:').first.trim();
      if (categoryId.isEmpty || entry.value is! Map) continue;
      final hold = RewardProbeHold.fromJson(categoryId, entry.value);
      if (hold == null || !hold.holdsCard(wanted)) continue;
      if (customer.isNotEmpty && hold.customerId.trim() != customer) continue;
      if (customer.isEmpty && hold.customerId.trim().isNotEmpty) continue;
      return _reverseHold(raw, hold, wanted, startPosition, endPosition);
    }
    return raw ?? '{}';
  }

  static String _reverseHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int startPosition,
    int endPosition,
  ) {
    final cards = hold.cards.toList();
    final visible = cards.indexWhere((card) => card.cardId == cardId);
    final start = (startPosition < endPosition ? startPosition : endPosition) - 1;
    final end = (startPosition < endPosition ? endPosition : startPosition) - 1;
    if (visible < 0 ||
        cards.length < 2 ||
        start < 0 ||
        end >= cards.length ||
        start == end ||
        visible < start ||
        visible > end) {
      return raw ?? '{}';
    }
    final reversed = [
      ...cards.sublist(0, start),
      ...cards.sublist(start, end + 1).reversed,
      ...cards.sublist(end + 1),
    ];
    return PromotionRewardTemplate.rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: reversed.first.cardId,
        reservationId: reversed.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: reversed,
      ),
    );
  }
}
