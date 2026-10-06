import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';
import 'package:net_app/domain/services/reward_probe_rotate.dart';

/// ترتيب طابور المعاينة عبر الفئات: أول كرت مُدخل هو الرأس عند الموضع 1
/// (`cards.first`)، والمواضع 1-based على `cards` كما تفعل ورقة القالب.
/// الرأس هو أول كرت يُصرف، وتدوير الطابور ينقل الرأس إلى الذيل.
void main() {
  test('rotating a queue moves the head to the tail without swapping one pair',
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
    final withThird = PromotionRewardTemplate.enqueueCrossCategoryHold(
      PromotionRewardTemplate.enqueueCrossCategoryHold(
        encoded,
        hold('cross-a', 'cat-9', customerId: 'cust-1'),
      ),
      hold('cross-c', 'cat-3', customerId: 'cust-1'),
    );
    // الطابور: cross-b (الرأس), cross-a, cross-c.
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(withThird,
              customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['cross-b', 'cross-a', 'cross-c'],
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
    // خطوة واحدة: الرأس cross-b إلى الذيل، ويتقدم ما بعده.
    expect(customer?.cards.map((card) => card.cardId),
        ['cross-a', 'cross-c', 'cross-b']);
    expect(customer?.cards.map((card) => card.reservationId), [
      'res-cross-a',
      'res-cross-c',
      'res-cross-b',
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
    // خطوتان إضافيتان على طابور من ثلاثة = دورة كاملة تعيد الترتيب الأصلي.
    final twice = RewardProbeRotate.rotateQueuedCard(
      rotated,
      cardId: 'cross-a',
      steps: 2,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(twice,
              customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['cross-b', 'cross-a', 'cross-c'],
    );
    expect(twice, withThird);
    expect(
      PromotionRewardTemplate.lookupHold(rotated, 'cat-1', customerId: 'cust-1')
          ?.cardId,
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
      PromotionRewardTemplate.lookupHold(otherCustomer, 'cat-1',
              customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['own-a'],
    );
  });
}
