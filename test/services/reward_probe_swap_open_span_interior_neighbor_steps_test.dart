import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_swap_open_span_interior_neighbor_steps.dart';

void main() {
  test('swaps the higher neighbor of a card steps ahead of the visible card', () {
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
            PromotionRewardTemplate.enqueueCrossCategoryHold(
              encoded,
              hold('cross-a', 'cat-9', customerId: 'cust-1'),
            ),
            hold('cross-c', 'cat-3', customerId: 'cust-1'),
          ),
          hold('cross-d', 'cat-4', customerId: 'cust-1'),
        ),
        hold('cross-e', 'cat-5', customerId: 'cust-1'),
      ),
      hold('cross-f', 'cat-6', customerId: 'cust-1'),
    );

    // queue: cross-b, cross-a, cross-c, cross-d, cross-e, cross-f
    // visible cross-a is inside span 1..6. Two steps higher is cross-d;
    // swap it with the card immediately higher (cross-e). Visible stays.
    final swapped = RewardProbeSwapOpenSpanInteriorNeighborSteps
        .swapOpenSpanInteriorNeighborSteps(
      withRest,
      cardId: 'cross-a',
      startPosition: 1,
      endPosition: 6,
      steps: 2,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      swapped,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-a',
      'cross-c',
      'cross-e',
      'cross-d',
      'cross-f',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-a',
      'res-cross-c',
      'res-cross-e',
      'res-cross-d',
      'res-cross-f',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeSwapOpenSpanInteriorNeighborSteps
          .swapOpenSpanInteriorNeighborSteps(
        swapped,
        cardId: 'cross-a',
        startPosition: 6,
        endPosition: 1,
        steps: 4,
        customerId: 'cust-1',
      ),
      swapped,
    );
    expect(
      RewardProbeSwapOpenSpanInteriorNeighborSteps
          .swapOpenSpanInteriorNeighborSteps(
        withRest,
        cardId: 'cross-a',
        startPosition: 1,
        endPosition: 6,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeSwapOpenSpanInteriorNeighborSteps
          .swapOpenSpanInteriorNeighborSteps(
        withRest,
        cardId: 'cross-f',
        startPosition: 1,
        endPosition: 6,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(swapped, 'cat-1', customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(swapped, customerId: '')
          ?.cardId,
      'shared-a',
    );
  });
}
