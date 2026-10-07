import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_delay_open_span_interior.dart';

void main() {
  test('delays the visible card one step inside the span without moving the ends', () {
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
    final delayed = RewardProbeDelayOpenSpanInterior.delayOpenSpanInterior(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 5,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      delayed,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-c',
      'cross-a',
      'cross-d',
      'cross-e',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-c',
      'res-cross-a',
      'res-cross-d',
      'res-cross-e',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeDelayOpenSpanInterior.delayOpenSpanInterior(
        delayed,
        cardId: 'cross-c',
        startPosition: 5,
        endPosition: 1,
        customerId: 'cust-1',
      ),
      delayed,
    );
    expect(
      RewardProbeDelayOpenSpanInterior.delayOpenSpanInterior(
        withRest,
        cardId: 'cross-b',
        startPosition: 1,
        endPosition: 5,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeDelayOpenSpanInterior.delayOpenSpanInterior(
        withRest,
        cardId: 'cross-a',
        startPosition: 1,
        endPosition: 5,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(delayed, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(delayed, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
