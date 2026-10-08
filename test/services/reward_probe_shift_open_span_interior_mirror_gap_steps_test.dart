import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_shift_open_span_interior_mirror_gap_steps.dart';

void main() {
  test('shifts cards between mirrored probe cards one step higher inside the span', () {
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
    var withRest = encoded;
    for (final card in [
      hold('cross-a', 'cat-9', customerId: 'cust-1'),
      hold('cross-c', 'cat-3', customerId: 'cust-1'),
      hold('cross-d', 'cat-4', customerId: 'cust-1'),
      hold('cross-e', 'cat-5', customerId: 'cust-1'),
      hold('cross-f', 'cat-6', customerId: 'cust-1'),
      hold('cross-g', 'cat-7', customerId: 'cust-1'),
      hold('cross-h', 'cat-8', customerId: 'cust-1'),
      hold('cross-i', 'cat-10', customerId: 'cust-1'),
    ]) {
      withRest = PromotionRewardTemplate.enqueueCrossCategoryHold(withRest, card);
    }

    // queue: cross-b, cross-a, cross-c, cross-d, cross-e, cross-f, cross-g, cross-h, cross-i
    // visible cross-e is inside span 1..9. Three steps place mirrors on cross-a and cross-h.
    // Gaps shift toward the higher end: c,d -> d,c and f,g -> g,f.
    final shifted = RewardProbeShiftOpenSpanInteriorMirrorGapSteps
        .shiftOpenSpanInteriorMirrorGapSteps(
      withRest,
      cardId: 'cross-e',
      startPosition: 1,
      endPosition: 9,
      steps: 3,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      shifted,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-a',
      'cross-d',
      'cross-c',
      'cross-e',
      'cross-g',
      'cross-f',
      'cross-h',
      'cross-i',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-a',
      'res-cross-d',
      'res-cross-c',
      'res-cross-e',
      'res-cross-g',
      'res-cross-f',
      'res-cross-h',
      'res-cross-i',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeShiftOpenSpanInteriorMirrorGapSteps
          .shiftOpenSpanInteriorMirrorGapSteps(
        shifted,
        cardId: 'cross-e',
        startPosition: 9,
        endPosition: 1,
        steps: 2,
        customerId: 'cust-1',
      ),
      shifted,
    );
    expect(
      RewardProbeShiftOpenSpanInteriorMirrorGapSteps
          .shiftOpenSpanInteriorMirrorGapSteps(
        withRest,
        cardId: 'cross-e',
        startPosition: 1,
        endPosition: 9,
        steps: 4,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeShiftOpenSpanInteriorMirrorGapSteps
          .shiftOpenSpanInteriorMirrorGapSteps(
        withRest,
        cardId: 'cross-b',
        startPosition: 1,
        endPosition: 9,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(shifted, 'cat-1', customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(shifted, customerId: '')
          ?.cardId,
      'shared-a',
    );
  });
}
