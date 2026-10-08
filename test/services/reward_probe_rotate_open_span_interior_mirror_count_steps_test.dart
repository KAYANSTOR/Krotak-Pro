import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_open_span_interior_mirror_count_steps.dart';

void main() {
  test('rotates the visible card with its mirrored cards several steps higher', () {
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
      ),
      hold('cross-g', 'cat-7', customerId: 'cust-1'),
    );

    // queue: cross-b, cross-a, cross-c, cross-d, cross-e, cross-f, cross-g
    // visible cross-d is inside span 1..7. Two steps toward the higher end rotate
    // cross-a, cross-d, cross-f into cross-d, cross-f, cross-a.
    // Endpoints and the cards between the mirrors stay.
    final rotated = RewardProbeRotateOpenSpanInteriorMirrorCountSteps
        .rotateOpenSpanInteriorMirrorCountSteps(
      withRest,
      cardId: 'cross-d',
      startPosition: 1,
      endPosition: 7,
      steps: 2,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-d',
      'cross-c',
      'cross-f',
      'cross-e',
      'cross-a',
      'cross-g',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-c',
      'res-cross-f',
      'res-cross-e',
      'res-cross-a',
      'res-cross-g',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeRotateOpenSpanInteriorMirrorCountSteps
          .rotateOpenSpanInteriorMirrorCountSteps(
        rotated,
        cardId: 'cross-f',
        startPosition: 7,
        endPosition: 1,
        steps: 3,
        customerId: 'cust-1',
      ),
      rotated,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorMirrorCountSteps
          .rotateOpenSpanInteriorMirrorCountSteps(
        withRest,
        cardId: 'cross-d',
        startPosition: 1,
        endPosition: 7,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorMirrorCountSteps
          .rotateOpenSpanInteriorMirrorCountSteps(
        withRest,
        cardId: 'cross-b',
        startPosition: 1,
        endPosition: 7,
        steps: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(rotated, 'cat-1', customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(rotated, customerId: '')
          ?.cardId,
      'shared-a',
    );
  });
}
