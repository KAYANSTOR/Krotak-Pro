import 'promotion_reward_template.dart';

/// يزيح الكروت بين الكرتين المقابلتين خطوة نحو الطرف الأدنى داخل مقطع المعاينة.
/// الكرت الظاهر والكرتان المقابلتان والطرفان لا يتحركون. كل جهة بين كرت مقابل
/// والكرت الظاهر تدور خطوة نحو الأدنى، ويعود أول كرت في الجهة إلى آخر موضع مفتوح.
/// الكروت خارج المقطع والحجوزات وموعد الانتهاء تبقى كما هي.
/// الإزاحة تقف قبل الطرفين ولا تخرج الكرتين المقابلتين من الداخل.
class RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack {
  const RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack._();

  static String shiftOpenSpanInteriorMirrorGapStepsBack(
    String? raw, {
    required String cardId,
    required int startPosition,
    required int endPosition,
    required int steps,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || startPosition < 1 || endPosition < 1 || steps < 3) {
      return raw ?? '{}';
    }
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _shiftHold(raw, cross, wanted, startPosition, endPosition, steps);
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
      return _shiftHold(raw, hold, wanted, startPosition, endPosition, steps);
    }
    return raw ?? '{}';
  }

  static String _shiftHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int startPosition,
    int endPosition,
    int steps,
  ) {
    final cards = hold.cards.toList();
    final visible = cards.indexWhere((card) => card.cardId == cardId);
    final start = (startPosition < endPosition ? startPosition : endPosition) - 1;
    final end = (startPosition < endPosition ? endPosition : startPosition) - 1;
    if (visible < 0 ||
        cards.length < 9 ||
        start < 0 ||
        end >= cards.length ||
        end - start < 8 ||
        visible <= start ||
        visible >= end ||
        steps < 3) {
      return raw ?? '{}';
    }
    final lower = visible - steps;
    final higher = visible + steps;
    if (lower <= start || higher >= end) {
      return raw ?? '{}';
    }
    final next = cards.toList();
    _rotateTowardLower(next, lower + 1, visible - 1);
    _rotateTowardLower(next, visible + 1, higher - 1);
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

  static void _rotateTowardLower(List<RewardProbeHeldCard> cards, int from, int to) {
    if (to - from < 1) return;
    final first = cards[from];
    for (var index = from; index < to; index++) {
      cards[index] = cards[index + 1];
    }
    cards[to] = first;
  }
}
