import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_reverse_open_span_interior_mirror_both_gaps.dart';

void main() {
  test('reverses both interior gaps around mirrored probe cards in one operation', () {
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
      hold('cross-a', 'cat-3', customerId: 'cust-1'),
      hold('cross-c', 'cat-4', customerId: 'cust-1'),
      hold('cross-d', 'cat-5', customerId: 'cust-1'),
      hold('cross-e', 'cat-6', customerId: 'cust-1'),
      hold('cross-f', 'cat-7', customerId: 'cust-1'),
      hold('cross-g', 'cat-8', customerId: 'cust-1'),
      hold('cross-h', 'cat-9', customerId: 'cust-1'),
      hold('cross-i', 'cat-10', customerId: 'cust-1'),
      hold('cross-j', 'cat-11', customerId: 'cust-1'),
      hold('cross-k', 'cat-12', customerId: 'cust-1'),
      hold('cross-l', 'cat-13', customerId: 'cust-1'),
      hold('cross-m', 'cat-14', customerId: 'cust-1'),
    ]) {
      withRest = PromotionRewardTemplate.enqueueCrossCategoryHold(withRest, card);
    }

    // queue: b a c d e f g h i j k l m
    // visible g index 6, span 1..13, steps 3. Mirrors d and j stay.
    // Inner gaps e,f and h,i reverse. Outer gaps a,c and k,l reverse.
    // Ends b,m and visible g stay.
    final reversed = RewardProbeReverseOpenSpanInteriorMirrorBothGaps
        .reverseOpenSpanInteriorMirrorBothGaps(
      withRest,
      cardId: 'cross-g',
      startPosition: 1,
      endPosition: 13,
      steps: 3,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      reversed,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-c',
      'cross-a',
      'cross-d',
      'cross-f',
      'cross-e',
      'cross-g',
      'cross-i',
      'cross-h',
      'cross-j',
      'cross-l',
      'cross-k',
      'cross-m',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-b',
      'res-cross-c',
      'res-cross-a',
      'res-cross-d',
      'res-cross-f',
      'res-cross-e',
      'res-cross-g',
      'res-cross-i',
      'res-cross-h',
      'res-cross-j',
      'res-cross-l',
      'res-cross-k',
      'res-cross-m',
    ]);
    expect(customer?.expiresAt, expires);
    expect(
      RewardProbeReverseOpenSpanInteriorMirrorBothGaps
          .reverseOpenSpanInteriorMirrorBothGaps(
        reversed,
        cardId: 'cross-g',
        startPosition: 13,
        endPosition: 1,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseOpenSpanInteriorMirrorBothGaps
          .reverseOpenSpanInteriorMirrorBothGaps(
        withRest,
        cardId: 'cross-g',
        startPosition: 1,
        endPosition: 13,
        steps: 2,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseOpenSpanInteriorMirrorBothGaps
          .reverseOpenSpanInteriorMirrorBothGaps(
        withRest,
        cardId: 'cross-g',
        startPosition: 1,
        endPosition: 13,
        steps: 4,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseOpenSpanInteriorMirrorBothGaps
          .reverseOpenSpanInteriorMirrorBothGaps(
        withRest,
        cardId: 'cross-b',
        startPosition: 1,
        endPosition: 13,
        steps: 3,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(reversed, 'cat-1', customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(reversed, customerId: '')
          ?.cardId,
      'shared-a',
    );

    var longer = withRest;
    for (final card in [
      hold('cross-n', 'cat-15', customerId: 'cust-1'),
      hold('cross-o', 'cat-16', customerId: 'cust-1'),
    ]) {
      longer = PromotionRewardTemplate.enqueueCrossCategoryHold(longer, card);
    }
    // queue: b a c d e f g h i j k l m n o
    // visible h index 7, span 1..15, steps 3. Mirrors e and k stay.
    // Inner gaps f,g and i,j reverse. Outer gaps a,c,d and l,m,n reverse.
    final counted = RewardProbeReverseOpenSpanInteriorMirrorBothGaps
        .reverseOpenSpanInteriorMirrorBothGaps(
      longer,
      cardId: 'cross-h',
      startPosition: 1,
      endPosition: 15,
      steps: 3,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(
        counted,
        customerId: 'cust-1',
      )?.cards.map((card) => card.cardId),
      [
        'cross-b',
        'cross-d',
        'cross-c',
        'cross-a',
        'cross-e',
        'cross-g',
        'cross-f',
        'cross-h',
        'cross-j',
        'cross-i',
        'cross-k',
        'cross-n',
        'cross-m',
        'cross-l',
        'cross-o',
      ],
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(
        counted,
        customerId: 'cust-1',
      )?.expiresAt,
      expires,
    );
  });
}
