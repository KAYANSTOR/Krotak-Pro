import 'promotion_reward_template.dart';

/// تبديل كرت طابور المعاينة مع كرت موضع يختاره المشغّل.
/// الموضع 1 هو أول صرف. التبديل يبادل الحجزين ولا يزيح بقية الطابور.
class RewardProbeSwap {
  const RewardProbeSwap._();

  static String swapQueuedCard(
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
      return _swapHold(raw, cross, wanted, position);
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
      return _swapHold(raw, hold, wanted, position);
    }
    return raw ?? '{}';
  }

  static String _swapHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int position,
  ) {
    final cards = hold.cards.toList();
    final index = cards.indexWhere((card) => card.cardId == cardId);
    if (index < 0 || cards.length < 2) return raw ?? '{}';
    final target = (position - 1).clamp(0, cards.length - 1);
    if (target == index) return raw ?? '{}';
    final current = cards[index];
    cards[index] = cards[target];
    cards[target] = current;
    return PromotionRewardTemplate.rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: cards.first.cardId,
        reservationId: cards.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: cards,
      ),
    );
  }
}
