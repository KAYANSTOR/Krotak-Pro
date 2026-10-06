import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_swap_open_span.dart';

void main() {
  test('swaps the endpoints of a span that does not start at the visible card', () {
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
    // visible cross-c is inside span 2..4, not at either endpoint.
    final swapped = RewardProbeSwapOpenSpan.swapOpenSpan(
      withRest,
      cardId: 'cross-c',
      startPosition: 2,
      endPosition: 4,
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
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-c',
      'res-cross-a',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeSwapOpenSpan.swapOpenSpan(
        swapped,
        cardId: 'cross-c',
        startPosition: 4,
        endPosition: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeSwapOpenSpan.swapOpenSpan(
        withRest,
        cardId: 'cross-b',
        startPosition: 3,
        endPosition: 4,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeSwapOpenSpan.swapOpenSpan(
        withRest,
        cardId: 'cross-c',
        startPosition: 2,
        endPosition: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(swapped, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(swapped, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
