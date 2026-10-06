import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_reverse_open_span_interior.dart';

void main() {
  test('reverses cards between span endpoints and leaves the endpoints in place', () {
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
    final reversed = RewardProbeReverseOpenSpanInterior.reverseOpenSpanInterior(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 5,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      reversed,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-d',
      'cross-c',
      'cross-a',
      'cross-e',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-c',
      'res-cross-a',
      'res-cross-e',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeReverseOpenSpanInterior.reverseOpenSpanInterior(
        reversed,
        cardId: 'cross-c',
        startPosition: 5,
        endPosition: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseOpenSpanInterior.reverseOpenSpanInterior(
        withRest,
        cardId: 'cross-b',
        startPosition: 3,
        endPosition: 5,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseOpenSpanInterior.reverseOpenSpanInterior(
        withRest,
        cardId: 'cross-c',
        startPosition: 2,
        endPosition: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(reversed, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(reversed, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
