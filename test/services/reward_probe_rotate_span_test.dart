import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_span.dart';

/// ترتيب الطابور: أول كرت مُدخل هو الرأس عند الموضع 1 (`cards.first`)،
/// والمواضع 1-based على `cards`. المقطع يبدأ من الرأس وينتهي عند الموضع المدخل،
/// شاملًا الطرفين. إذا كان الموضع المدخل هو موضع الرأس نفسه فلا يُكتب شيء.
void main() {
  test('rotates only the span between the visible card and the chosen position',
      () {
    final expires = DateTime.utc(2026, 10, 12);
    RewardProbeHold hold(String cardId, String categoryId,
        {String customerId = ''}) {
      return RewardProbeHold(
        categoryId: categoryId,
        cardId: cardId,
        reservationId: 'res-$cardId',
        expiresAt: expires,
        customerId: customerId,
      );
    }

    final encoded = PromotionRewardTemplate.enqueueCrossCategoryHold(
      PromotionRewardTemplate.enqueueHold(
        PromotionRewardTemplate.enqueueCrossCategoryHold(
          null,
          hold('shared-a', 'cat-shared'),
        ),
        hold('own-a', 'cat-1', customerId: 'cust-1'),
      ),
      hold('cross-b', 'cat-2', customerId: 'cust-1'),
    );
    final withRest = PromotionRewardTemplate.enqueueCrossCategoryHold(
      PromotionRewardTemplate.enqueueCrossCategoryHold(
        PromotionRewardTemplate.enqueueCrossCategoryHold(
          encoded,
          hold('cross-a', 'cat-9', customerId: 'cust-1'),
        ),
        hold('cross-c', 'cat-3', customerId: 'cust-1'),
      ),
      hold('cross-d', 'cat-4', customerId: 'cust-1'),
    );
    // الطابور: cross-b (الرأس), cross-a, cross-c, cross-d.

    final rotated = RewardProbeRotateSpan.rotateQueuedSpan(
      withRest,
      cardId: 'cross-b',
      position: 4,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-a',
      'cross-c',
      'cross-d',
      'cross-b',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-a',
      'res-cross-c',
      'res-cross-d',
      'res-cross-b',
    ]);
    expect(customer?.expiresAt, expires);
    // خطوة أخرى على المقطع كاملًا (الرأس الجديد في الموضع 1).
    final twice = RewardProbeRotateSpan.rotateQueuedSpan(
      rotated,
      cardId: 'cross-a',
      position: 4,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(twice,
              customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['cross-c', 'cross-d', 'cross-b', 'cross-a'],
    );
    // تدوير المقطع خطوة واحدة بعدد كروت الطابور يعيد الترتيب الأصلي.
    final thrice = RewardProbeRotateSpan.rotateQueuedSpan(
      twice,
      cardId: 'cross-c',
      position: 4,
      customerId: 'cust-1',
    );
    final fourth = RewardProbeRotateSpan.rotateQueuedSpan(
      thrice,
      cardId: 'cross-d',
      position: 4,
      customerId: 'cust-1',
    );
    expect(fourth, withRest);
    // الموضع المدخل هو موضع الرأس نفسه، أو خارج طول الطابور: لا يُكتب شيء.
    expect(
      RewardProbeRotateSpan.rotateQueuedSpan(
        withRest,
        cardId: 'cross-b',
        position: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateSpan.rotateQueuedSpan(
        withRest,
        cardId: 'cross-b',
        position: 9,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(rotated, 'cat-1', customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(rotated, customerId: '')
          ?.cardId,
      'shared-a',
    );
  });
}
