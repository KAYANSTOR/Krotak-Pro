import 'promotion_reward_template.dart';

/// يؤخّر الكرت الظاهر خطوة واحدة داخل مقطع طابور المعاينة دون تحريك الطرفين.
/// الكرت الظاهر يحدد الطابور ويجب أن يقع بين الطرفين لا عليهما.
/// الكروت خارج المقطع والحجوزات وموعد الانتهاء تبقى كما هي.
class RewardProbeDelayOpenSpanInterior {
  const RewardProbeDelayOpenSpanInterior._();

  static String delayOpenSpanInterior(
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
      return _delayHold(raw, cross, wanted, startPosition, endPosition);
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
      return _delayHold(raw, hold, wanted, startPosition, endPosition);
    }
    return raw ?? '{}';
  }

  static String _delayHold(
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
        cards.length < 4 ||
        start < 0 ||
        end >= cards.length ||
        end - start < 3 ||
        visible <= start ||
        visible >= end) {
      return raw ?? '{}';
    }
    if (visible <= start + 1) return raw ?? '{}';
    final next = cards.toList();
    final current = next[visible];
    next[visible] = next[visible - 1];
    next[visible - 1] = current;
    return PromotionRewardTemplate.rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: next.first.cardId,
        reservationId: next.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: next,
      ),
    );
  }
}
