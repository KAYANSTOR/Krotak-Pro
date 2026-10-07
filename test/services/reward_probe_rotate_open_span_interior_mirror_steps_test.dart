import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate_open_span_interior_mirror_steps.dart';

void main() {
  test('rotates the visible card with its mirrored cards one step higher', () {
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
    // visible cross-c is inside span 1..6. One step rotates
    // cross-a, cross-c, cross-d into cross-d, cross-a, cross-c.
    // Endpoints and the card between the mirrors stay.
    final rotated = RewardProbeRotateOpenSpanInteriorMirrorSteps
        .rotateOpenSpanInteriorMirrorSteps(
      withRest,
      cardId: 'cross-c',
      startPosition: 1,
      endPosition: 6,
      steps: 1,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      rotated,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-d',
      'cross-a',
      'cross-c',
      'cross-e',
      'cross-f',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-d',
      'res-cross-a',
      'res-cross-c',
      'res-cross-e',
      'res-cross-f',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeRotateOpenSpanInteriorMirrorSteps
          .rotateOpenSpanInteriorMirrorSteps(
        rotated,
        cardId: 'cross-a',
        startPosition: 6,
        endPosition: 1,
        steps: 2,
        customerId: 'cust-1',
      ),
      rotated,
    );
    expect(
      RewardProbeRotateOpenSpanInteriorMirrorSteps
          .rotateOpenSpanInteriorMirrorSteps(
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
      RewardProbeRotateOpenSpanInteriorMirrorSteps
          .rotateOpenSpanInteriorMirrorSteps(
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
