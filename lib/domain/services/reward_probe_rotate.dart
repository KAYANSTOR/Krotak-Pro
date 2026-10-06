import 'promotion_reward_template.dart';

/// تدوير طابور المعاينة الذي يحمل الكرت الظاهر بعدد خطوات يختاره المشغّل.
/// الخطوة 1 تنقل أول كرت إلى الذيل وتُبقي الترتيب النسبي للبقية.
/// التدوير لا يبادل موضعين فقط ولا يزيح كرتًا واحدًا إلى موضع مطلق.
class RewardProbeRotate {
  const RewardProbeRotate._();

  static String rotateQueuedCard(
    String? raw, {
    required String cardId,
    required int steps,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty || steps < 1) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: customer,
    );
    if (cross != null && cross.holdsCard(wanted)) {
      return _rotateHold(raw, cross, wanted, steps);
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
      return _rotateHold(raw, hold, wanted, steps);
    }
    return raw ?? '{}';
  }

  static String _rotateHold(
    String? raw,
    RewardProbeHold hold,
    String cardId,
    int steps,
  ) {
    final cards = hold.cards.toList();
    if (!cards.any((card) => card.cardId == cardId) || cards.length < 2) {
      return raw ?? '{}';
    }
    final shift = steps % cards.length;
    if (shift == 0) return raw ?? '{}';
    final rotated = [...cards.sublist(shift), ...cards.sublist(0, shift)];
    return PromotionRewardTemplate.rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: rotated.first.cardId,
        reservationId: rotated.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: rotated,
      ),
    );
  }
}
