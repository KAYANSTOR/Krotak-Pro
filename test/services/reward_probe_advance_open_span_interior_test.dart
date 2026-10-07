import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_advance_open_span_interior.dart';

void main() {
  test('advances the visible card one step inside the span without moving the ends', () {
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
    final advanced = RewardProbeAdvanceOpenSpanInterior.advanceOpenSpanInterior(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 5,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      advanced,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-a',
      'cross-d',
      'cross-c',
      'cross-e',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-a',
      'res-cross-d',
      'res-cross-c',
      'res-cross-e',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeAdvanceOpenSpanInterior.advanceOpenSpanInterior(
        advanced,
        cardId: 'cross-c',
        startPosition: 5,
        endPosition: 1,
        customerId: 'cust-1',
      ),
      advanced,
    );
    expect(
      RewardProbeAdvanceOpenSpanInterior.advanceOpenSpanInterior(
        withRest,
        cardId: 'cross-b',
        startPosition: 1,
        endPosition: 5,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeAdvanceOpenSpanInterior.advanceOpenSpanInterior(
        withRest,
        cardId: 'cross-a',
        startPosition: 2,
        endPosition: 4,
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
