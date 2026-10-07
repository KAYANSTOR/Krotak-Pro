import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_swap_open_span_interior_mirror_steps.dart';

void main() {
  test('swaps the two cards mirrored by steps around the visible card', () {
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
    // visible cross-c is inside span 1..6. One step each side swaps
    // cross-a with cross-d. Visible and endpoints stay.
    final swapped = RewardProbeSwapOpenSpanInteriorMirrorSteps
        .swapOpenSpanInteriorMirrorSteps(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 6,
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      swapped,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-d',
      'cross-c',
      'cross-a',
      'cross-e',
      'cross-f',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-c',
      'res-cross-a',
      'res-cross-e',
      'res-cross-f',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeSwapOpenSpanInteriorMirrorSteps
          .swapOpenSpanInteriorMirrorSteps(
        swapped,
        cardId: 'cross-c',
        startPosition: 6,
        endPosition: 1,
        steps: 2,
        customerId: 'cust-1',
      ),
      swapped,
    );
    expect(
      RewardProbeSwapOpenSpanInteriorMirrorSteps
          .swapOpenSpanInteriorMirrorSteps(
        withRest,
        cardId: 'cross-c',
        startPosition: 1,
        endPosition: 6,
        steps: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeSwapOpenSpanInteriorMirrorSteps
          .swapOpenSpanInteriorMirrorSteps(
        withRest,
        cardId: 'cross-b',
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
