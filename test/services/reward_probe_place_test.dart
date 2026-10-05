import 'package:flutter_test/flutter_test.dart';
import 'package:net_flutter/domain/services/promotion_reward_template.dart';
import 'package:net_flutter/domain/services/reward_probe_place.dart';

void main() {
  test('placing a queued card moves only that card and keeps reservations', () {
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
    final placed = RewardProbePlace.placeQueuedCard(
      withThird,
      cardId: 'cross-c',
      position: 2,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      placed,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), ['cross-b', 'cross-c', 'cross-a']);
    expect(customer?.expiresAt, expires);
    expect(customer?.cards[1].reservationId, 'res-cross-c');
    expect(
      RewardProbePlace.placeQueuedCard(
        placed,
        cardId: 'cross-c',
        position: 2,
        customerId: 'cust-1',
      ),
      placed,
    );
    final tailed = RewardProbePlace.placeQueuedCard(
      placed,
      cardId: 'cross-b',
      position: 99,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(tailed, customerId: 'cust-1')?.cards.map((card) => card.cardId),
      ['cross-c', 'cross-a', 'cross-b'],
    );
    expect(
      PromotionRewardTemplate.lookupHold(placed, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(placed)?.cardId,
      'shared-a',
    );
    final otherCustomer = RewardProbePlace.placeQueuedCard(
      placed,
      cardId: 'own-a',
      position: 1,
    );
    expect(
      PromotionRewardTemplate.lookupHold(otherCustomer, 'cat-1', customerId: 'cust-1')?.cards.map((card) => card.cardId),
      ['own-a'],
    );
  });
}
