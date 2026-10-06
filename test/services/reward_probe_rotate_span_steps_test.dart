import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_span_steps.dart';

/// ترتيب الطابور: أول كرت مُدخل هو الرأس عند الموضع 1 (`cards.first`)،
/// والمواضع 1-based على `cards`. المقطع يبدأ من الرأس وينتهي عند الموضع المدخل،
/// شاملًا الطرفين، وعدد الخطوات لا يغيّر موضع ما خارج المقطع.
void main() {
  test('rotates only the span by operator steps up to the chosen position', () {
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

    final rotated = RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
      withRest,
      cardId: 'cross-b',
      position: 4,
      steps: 2,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-c',
      'cross-d',
      'cross-b',
      'cross-a',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-c',
      'res-cross-d',
      'res-cross-b',
      'res-cross-a',
    ]);
    expect(customer?.expiresAt, expires);
    // عدد خطوات يساوي طول المقطع (كروت الطابور) لا يغيّر الترتيب.
    expect(
      RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
        rotated,
        cardId: 'cross-c',
        position: 4,
        steps: 4,
        customerId: 'cust-1',
      ),
      rotated,
    );
    // الموضع المدخل هو موضع الرأس نفسه، أو خارج طول الطابور: لا يُكتب شيء.
    expect(
      RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
        withRest,
        cardId: 'cross-b',
        position: 1,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
        withRest,
        cardId: 'cross-b',
        position: 9,
        steps: 1,
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
    expect(
      RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
        withRest,
        cardId: 'own-a',
        position: 1,
        steps: 2,
      ),
      withRest,
    );
  });
}
