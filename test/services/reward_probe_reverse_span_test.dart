import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_reverse_span.dart';

/// ترتيب الطابور: أول كرت مُدخل هو الرأس عند الموضع 1 (`cards.first`)،
/// والمواضع 1-based على `cards`. المقطع يبدأ من الرأس وينتهي عند الموضع المدخل،
/// شاملًا الطرفين، وعكسه لا يحرّك ما خارجه. عكس المقطع مرتين يعيد الأصل.
void main() {
  test(
      'reverses only the span between the visible card and the chosen position',
      () {
    final expires = DateTime.utc(2026, 10, 12);
    RewardProbeHold hold(String cardId, String categoryId,
        {String customerId = ''}) {
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
    // الطابور: cross-b (الرأس), cross-a, cross-c, cross-d.

    final reversed = RewardProbeReverseSpan.reverseQueuedSpan(
      withRest,
      cardId: 'cross-b',
      position: 4,
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      reversed,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), [
      'cross-d',
      'cross-c',
      'cross-a',
      'cross-b',
    ]);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-d',
      'res-cross-c',
      'res-cross-a',
      'res-cross-b',
    ]);
    expect(customer?.expiresAt, expires);
    // الرأس بعد العكس هو cross-d؛ عكس المقطع نفسه يعيد الترتيب الأصلي.
    expect(
      RewardProbeReverseSpan.reverseQueuedSpan(
        reversed,
        cardId: 'cross-d',
        position: 4,
        customerId: 'cust-1',
      ),
      withRest,
    );
    // الموضع المدخل هو موضع الرأس نفسه، أو خارج طول الطابور: لا يُكتب شيء.
    expect(
      RewardProbeReverseSpan.reverseQueuedSpan(
        withRest,
        cardId: 'cross-b',
        position: 1,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      RewardProbeReverseSpan.reverseQueuedSpan(
        withRest,
        cardId: 'cross-b',
        position: 9,
        customerId: 'cust-1',
      ),
      withRest,
    );
    expect(
      PromotionRewardTemplate.lookupHold(reversed, 'cat-1',
              customerId: 'cust-1')
          ?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(reversed, customerId: '')
          ?.cardId,
      'shared-a',
    );
  });
}
