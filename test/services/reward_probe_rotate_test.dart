import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate.dart';

void main() {
  test('rotating a queue moves the head to the tail without swapping one pair', () {
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
    final withThird = PromotionRewardTemplate.enqueueCrossCategoryHold(
      PromotionRewardTemplate.enqueueCrossCategoryHold(
        encoded,
        hold('cross-a', 'cat-9', customerId: 'cust-1'),
      ),
      hold('cross-c', 'cat-3', customerId: 'cust-1'),
    );
    final rotated = RewardProbeRotate.rotateQueuedCard(
      withThird,
      cardId: 'cross-c',
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), ['cross-a', 'cross-b', 'cross-c']);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-a',
      'res-cross-b',
      'res-cross-c',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeRotate.rotateQueuedCard(
        rotated,
        cardId: 'cross-c',
        steps: 3,
        customerId: 'cust-1',
      ),
      rotated,
    );
    final twice = RewardProbeRotate.rotateQueuedCard(
      rotated,
      cardId: 'cross-a',
      steps: 2,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(twice, customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['cross-c', 'cross-a', 'cross-b'],
    );
    expect(
      PromotionRewardTemplate.lookupHold(rotated, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(rotated)?.cardId,
      'shared-a',
    );
    final otherCustomer = RewardProbeRotate.rotateQueuedCard(
      rotated,
      cardId: 'own-a',
      steps: 1,
    );
    expect(
      PromotionRewardTemplate.lookupHold(otherCustomer, 'cat-1', customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['own-a'],
    );
  });
}
