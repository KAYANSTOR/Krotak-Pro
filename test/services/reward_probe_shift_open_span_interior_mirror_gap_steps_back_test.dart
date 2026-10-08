import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_shift_open_span_interior_mirror_gap_steps_back.dart';

void main() {
  test('shifts cards between mirrored probe cards one step lower inside the span', () {
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
    final shifted = RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
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
      RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
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
      RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
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
      RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
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

    var longer = withRest;
    for (final card in [
      hold('cross-j', 'cat-11', customerId: 'cust-1'),
      hold('cross-k', 'cat-12', customerId: 'cust-1'),
    ]) {
      longer = PromotionRewardTemplate.enqueueCrossCategoryHold(longer, card);
    }
    // queue: b a c d e f g h i j k. Visible f, span 1..11, steps 4.
    // Mirrors a and j and ends b and k stay. Gaps move toward the lower end.
    final lowered = RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
        .shiftOpenSpanInteriorMirrorGapStepsBack(
      longer,
      cardId: 'cross-f',
      startPosition: 1,
      endPosition: 11,
      steps: 4,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(
        lowered,
        customerId: 'cust-1',
      )?.cards.map((card) => card.cardId),
      [
        'cross-b',
        'cross-a',
        'cross-d',
        'cross-e',
        'cross-c',
        'cross-f',
        'cross-h',
        'cross-i',
        'cross-g',
        'cross-j',
        'cross-k',
      ],
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(
        lowered,
        customerId: 'cust-1',
      )?.expiresAt,
      expires,
    );
  });
}
