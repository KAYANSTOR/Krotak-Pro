import 'promotion_reward_template.dart';

/// يبدّل الكرت الظاهر مع الكرت الذي يبعد عنه بعدد خطوات داخل مقطع المعاينة.
/// الطرفان لا يتحركان، وبقية الداخل لا تنزاح. الكرت الظاهر يحدد الطابور ويقع بين الطرفين.
/// الكروت خارج المقطع والحجوزات وموعد الانتهاء تبقى كما هي.
/// التبديل يقف قبل الطرف الأعلى ولا يلفّ داخل المقطع.
class RewardProbeSwapOpenSpanInteriorSteps {
  const RewardProbeSwapOpenSpanInteriorSteps._();

  static String swapOpenSpanInteriorSteps(
    String? raw, {
    required String cardId,
    required int startPosition,
    required int endPosition,
    required int steps,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return raw ?? '{}';
    }
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _swapHold(
        raw,
        cross,
        wanted,
        startPosition,
        endPosition,
        steps,
      );
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
      return _swapHold(
        raw,
        hold,
        wanted,
        startPosition,
        endPosition,
        steps,
      );
    }
    return raw ?? '{}';
  }

  static String _swapHold(
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
        cards.length < 4 ||
        start < 0 ||
        end >= cards.length ||
        end - start < 3 ||
        visible <= start ||
        visible >= end ||
        steps < 1) {
      return raw ?? '{}';
    }
    final target = visible + steps;
    if (target >= end) return raw ?? '{}';
    final next = cards.toList();
    final current = next[visible];
    next[visible] = next[target];
    next[target] = current;
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
