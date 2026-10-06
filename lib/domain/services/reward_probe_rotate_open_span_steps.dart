import 'promotion_reward_template.dart';

/// تدوير مقطع طابور المعاينة بين موضعين يختارهما المشغّل بعدد خطوات.
/// المقطع لا يُشترط أن يبدأ من الكرت الظاهر؛ الكرت الظاهر يحدد الطابور ويجب أن يقع داخل المقطع.
/// الكروت خارج المقطع تبقى في أماكنها. الحجوزات وموعد الانتهاء يبقيان.
class RewardProbeRotateOpenSpanSteps {
  const RewardProbeRotateOpenSpanSteps._();

  static String rotateOpenSpanSteps(
    String? raw, {
    required String cardId,
    required int startPosition,
    required int endPosition,
    required int steps,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || startPosition < 1 || endPosition < 1 || steps < 1) {
      return raw ?? '{}';
    }
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _rotateHold(raw, cross, wanted, startPosition, endPosition, steps);
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
      return _rotateHold(raw, hold, wanted, startPosition, endPosition, steps);
    }
    return raw ?? '{}';
  }

  static String _rotateHold(
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
        cards.length < 2 ||
        start < 0 ||
        end >= cards.length ||
        start == end ||
        visible < start ||
        visible > end) {
      return raw ?? '{}';
    }
    final span = cards.sublist(start, end + 1);
    final shift = steps % span.length;
    if (shift == 0) return raw ?? '{}';
    final rotated = [...span.sublist(shift), ...span.sublist(0, shift)];
    final next = [
      ...cards.sublist(0, start),
      ...rotated,
      ...cards.sublist(end + 1),
    ];
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
