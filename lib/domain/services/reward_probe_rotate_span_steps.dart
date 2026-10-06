import 'promotion_reward_template.dart';

/// تدوير مقطع طابور المعاينة بعدد خطوات يختاره المشغّل حتى موضع طرف المقطع.
/// كل خطوة تنقل أول كرت في المقطع إلى نهايته. الكروت خارج المقطع تبقى في أماكنها.
/// الحجوزات تبقى مربوطة بكل كرت. هذا ليس تدويرًا للطابور كله ولا خطوة واحدة فقط.
class RewardProbeRotateSpanSteps {
  const RewardProbeRotateSpanSteps._();

  static String rotateQueuedSpanSteps(
    String? raw, {
    required String cardId,
    required int position,
    required int steps,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || position < 1 || steps < 1) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _rotateHold(raw, cross, wanted, position, steps);
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
      return _rotateHold(raw, hold, wanted, position, steps);
    }
    return raw ?? '{}';
  }

  static String _rotateHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int position,
    int steps,
  ) {
    final cards = hold.cards.toList();
    final from = cards.indexWhere((card) => card.cardId == cardId);
    final to = position - 1;
    if (from < 0 || cards.length < 2 || to < 0 || to >= cards.length || to == from) {
      return raw ?? '{}';
    }
    final start = from < to ? from : to;
    final end = from < to ? to : from;
    final span = cards.sublist(start, end + 1);
    if (span.length < 2) return raw ?? '{}';
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
