import 'promotion_reward_template.dart';

/// عكس مقطع طابور المعاينة بين الكرت الظاهر وموضع يختاره المشغّل.
/// الكروت خارج المقطع تبقى في أماكنها. الحجوزات تبقى مربوطة بكل كرت.
class RewardProbeReverseSpan {
  const RewardProbeReverseSpan._();

  static String reverseQueuedSpan(
    String? raw, {
    required String cardId,
    required int position,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || position < 1) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _reverseHold(raw, cross, wanted, position);
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
      return _reverseHold(raw, hold, wanted, position);
    }
    return raw ?? '{}';
  }

  static String _reverseHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int position,
  ) {
    final cards = hold.cards.toList();
    final from = cards.indexWhere((card) => card.cardId == cardId);
    final to = position - 1;
    if (from < 0 || cards.length < 2 || to < 0 || to >= cards.length || to == from) {
      return raw ?? '{}';
    }
    final start = from < to ? from : to;
    final end = from < to ? to : from;
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
