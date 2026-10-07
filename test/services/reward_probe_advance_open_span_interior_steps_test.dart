import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_advance_open_span_interior_steps.dart';

void main() {
  test('advances the visible card by steps inside the span without moving the ends', () {
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
    // visible cross-a sits inside span 1..5. Two steps toward the higher end.
    final advanced = RewardProbeAdvanceOpenSpanInteriorSteps.advanceOpenSpanInteriorSteps(
      withRest,
      cardId: 'cross-a',
      startPosition: 1,
      endPosition: 5,
      steps: 2,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      advanced,
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
      RewardProbeAdvanceOpenSpanInteriorSteps.advanceOpenSpanInteriorSteps(
        advanced,
        cardId: 'cross-a',
        startPosition: 5,
        endPosition: 1,
        steps: 1,
        customerId: 'cust-1',
      ),
      advanced,
    );
    expect(
      RewardProbeAdvanceOpenSpanInteriorSteps.advanceOpenSpanInteriorSteps(
        withRest,
        cardId: 'cross-a',
        startPosition: 1,
        endPosition: 5,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeAdvanceOpenSpanInteriorSteps.advanceOpenSpanInteriorSteps(
        withRest,
        cardId: 'cross-e',
        startPosition: 1,
        endPosition: 5,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(advanced, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(advanced, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
