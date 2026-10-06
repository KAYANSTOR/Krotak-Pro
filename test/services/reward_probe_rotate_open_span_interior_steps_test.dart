import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_open_span_interior_steps.dart';

void main() {
  test('rotates cards between span ends without moving the ends', () {
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
          PromotionRewardTemplate.enqueueCrossCategoryHold(
            encoded,
            hold('cross-a', 'cat-9', customerId: 'cust-1'),
          ),
          hold('cross-c', 'cat-3', customerId: 'cust-1'),
        ),
        hold('cross-d', 'cat-4', customerId: 'cust-1'),
      ),
      hold('cross-e', 'cat-5', customerId: 'cust-1'),
    );

    // queue: cross-b, cross-a, cross-c, cross-d, cross-e
    // visible cross-c sits inside span 1..5, not on an endpoint.
    final rotated = RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 5,
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-c',
      'cross-d',
      'cross-a',
      'cross-e',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-c',
      'res-cross-d',
      'res-cross-a',
      'res-cross-e',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
        rotated,
        cardId: 'cross-c',
        startPosition: 5,
        endPosition: 1,
        steps: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
        withRest,
        cardId: 'cross-c',
        startPosition: 1,
        endPosition: 5,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
        withRest,
        cardId: 'cross-b',
        startPosition: 3,
        endPosition: 5,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
        withRest,
        cardId: 'cross-c',
        startPosition: 1,
        endPosition: 3,
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
