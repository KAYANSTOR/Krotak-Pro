import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_open_span_steps_backward.dart';

void main() {
  test('rotates a span backward without starting at the visible card', () {
    final expires = DateTime.utc(2026, 10, 12);
    RewardProbeHold hold(String cardId, String categoryId, {String customerId = ''}) {
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

    // queue: cross-b, cross-a, cross-c, cross-d
    // visible cross-c is inside span 2..4, not at its start.
    // one backward step moves cross-d to the front of the span.
    final rotated = RewardProbeRotateOpenSpanStepsBackward.rotateOpenSpanStepsBackward(
      withRest,
      cardId: 'cross-c',
      startPosition: 2,
      endPosition: 4,
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-d',
      'cross-a',
      'cross-c',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-a',
      'res-cross-c',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeRotateOpenSpanStepsBackward.rotateOpenSpanStepsBackward(
        rotated,
        cardId: 'cross-c',
        startPosition: 2,
        endPosition: 4,
        steps: 3,
        customerId: 'cust-1',
      ),
      rotated,
    );
    expect(
      RewardProbeRotateOpenSpanStepsBackward.rotateOpenSpanStepsBackward(
        withRest,
        cardId: 'cross-b',
        startPosition: 3,
        endPosition: 4,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(rotated, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(rotated, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
