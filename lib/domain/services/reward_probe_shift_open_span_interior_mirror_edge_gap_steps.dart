import 'promotion_reward_template.dart';

/// يزيح في عملية واحدة الكروت بين كل كرت مقابل وطرف المقطع خطوة نحو الأعلى.
/// حقل الخطوات هو مسافة الكرتين المقابلتين عن الكرت الظاهر.
/// الكرت الظاهر والكرتان المقابلتان والطرفان لا يتحركون.
/// كل جهة بين كرت مقابل وطرف المقطع تدور خطوة نحو الأعلى،
/// ويعود آخر كرت في الجهة إلى أول موضع مفتوح.
/// الكروت خارج المقطع والحجوزات وموعد الانتهاء تبقى كما هي.
class RewardProbeShiftOpenSpanInteriorMirrorEdgeGapSteps {
  const RewardProbeShiftOpenSpanInteriorMirrorEdgeGapSteps._();

  static String shiftOpenSpanInteriorMirrorEdgeGapSteps(
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
        cards.length < 13 ||
        start < 0 ||
        end >= cards.length ||
        end - start < 12 ||
        visible <= start ||
        visible >= end ||
        steps < 3) {
      return raw ?? '{}';
    }
    final lower = visible - steps;
    final higher = visible + steps;
    if (lower <= start || higher >= end || lower < start + 3 || higher > end - 3) {
      return raw ?? '{}';
    }
    final next = cards.toList();
    _rotateTowardHigher(next, start + 1, lower - 1);
    _rotateTowardHigher(next, higher + 1, end - 1);
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

  static void _rotateTowardHigher(List<RewardProbeHeldCard> cards, int from, int to) {
    if (to - from < 1) return;
    final last = cards[to];
    for (var index = to; index > from; index--) {
      cards[index] = cards[index - 1];
    }
    cards[from] = last;
  }
}
