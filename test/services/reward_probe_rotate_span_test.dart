import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_span.dart';

void main() {
  test('rotates only the span between the visible card and the chosen position', () {
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

    final rotated = RewardProbeRotateSpan.rotateQueuedSpan(
      withRest,
      cardId: 'cross-b',
      position: 4,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-a',
      'cross-c',
      'cross-d',
      'cross-b',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-a',
      'res-cross-c',
      'res-cross-d',
      'res-cross-b',
    ]);
    expect(customer?.expiresAt, expires);
    final twice = RewardProbeRotateSpan.rotateQueuedSpan(
      rotated,
      cardId: 'cross-c',
      position: 4,
      customerId: 'cust-1',
    );
    final thrice = RewardProbeRotateSpan.rotateQueuedSpan(
      twice,
      cardId: 'cross-d',
      position: 4,
      customerId: 'cust-1',
    );
    expect(thrice, withRest);
    expect(
      RewardProbeRotateSpan.rotateQueuedSpan(
        withRest,
        cardId: 'cross-b',
        position: 2,
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
