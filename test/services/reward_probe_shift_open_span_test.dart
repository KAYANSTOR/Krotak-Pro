import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_shift_open_span.dart';

void main() {
  test('shifts a span that does not start at the visible card toward the end', () {
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
    // visible cross-c is inside span 2..3, not an endpoint requirement.
    final shifted = RewardProbeShiftOpenSpan.shiftOpenSpan(
      withRest,
      cardId: 'cross-c',
      startPosition: 2,
      endPosition: 3,
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      shifted,
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
      RewardProbeShiftOpenSpan.shiftOpenSpan(
        shifted,
        cardId: 'cross-a',
        startPosition: 3,
        endPosition: 4,
        steps: 1,
        customerId: 'cust-1',
      ),
      shifted,
    );
    expect(
      RewardProbeShiftOpenSpan.shiftOpenSpan(
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
      RewardProbeShiftOpenSpan.shiftOpenSpan(
        withRest,
        cardId: 'cross-c',
        startPosition: 2,
        endPosition: 3,
        steps: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeShiftOpenSpan.shiftOpenSpan(
        withRest,
        cardId: 'cross-c',
        startPosition: 2,
        endPosition: 2,
        steps: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(shifted, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(shifted, customerId: '')?.cardId,
      'shared-a',
    );
  });
}
