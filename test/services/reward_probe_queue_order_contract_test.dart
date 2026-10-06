import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';

/// عقد ترتيب وتنسيق طابور المعاينة عبر الفئات — يُثبّت ما تفترضه ورقة القالب
/// وكل عمليات الطابور (النقل، التبديل، التدوير، العكس):
///
/// 1. الرأس هو أول كرت مُدخل (`cards.first`) وهو أول كرت يُصرف، وموضعه 1.
/// 2. مصفوفة `queue` **تتضمن الرأس** في أولها، ومواضع المشغّل 1-based عليها.
/// 3. الكرت الجديد يُلحق بالذيل، وإعادة إدخال كرت موجود تنقله إلى الذيل دون
///    تكراره.
/// 4. الترميز/القراءة يحفظان الترتيب نفسه (لا انزياح ولا فقد ولا تكرار).
void main() {
  test('the cross-category queue keeps the first enqueued card at the head',
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

    final holdAtHead = PromotionRewardTemplate.lookupCrossCategoryHold(
      withRest,
      customerId: 'cust-1',
    );
    // (1) الرأس = أول كرت أُدخل، وموضعه 1.
    expect(holdAtHead?.cards.first.cardId, 'cross-b');
    expect(holdAtHead?.cardId, 'cross-b');
    expect(holdAtHead?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-a',
      'cross-c',
      'cross-d',
    ]);
    // (2) `queue` في التنسيق المخزّن تتضمن الرأس أولًا، و`cardId` يطابقه.
    expect(withRest, contains('"cardId":"cross-b"'));
    expect(
      withRest,
      contains('"queue":[{"cardId":"cross-b"'),
      reason: 'مصفوفة الطابور تبدأ بالرأس نفسه',
    );
    // (4) القراءة ثم إعادة الترميز تحفظان الترتيب نفسه (بلا فقد أو تكرار).
    final reread = PromotionRewardTemplate.lookupCrossCategoryHold(
      withRest,
      customerId: 'cust-1',
    )!;
    final reencoded = PromotionRewardTemplate.rememberHold('{}', reread);
    final afterRoundTrip = PromotionRewardTemplate.lookupCrossCategoryHold(
      reencoded,
      customerId: 'cust-1',
    );
    expect(afterRoundTrip?.cards.map((card) => card.cardId), [
      'cross-b',
      'cross-a',
      'cross-c',
      'cross-d',
    ]);
    expect(afterRoundTrip?.expiresAt, expires);
    expect(afterRoundTrip?.cardId, 'cross-b');

    // (3) إعادة إدخال كرت قائم تنقله إلى الذيل دون تكرار.
    final reappended = PromotionRewardTemplate.enqueueCrossCategoryHold(
      withRest,
      hold('cross-a', 'cat-9', customerId: 'cust-1'),
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(reappended,
              customerId: 'cust-1')
          ?.cards
          .map((card) => card.cardId),
      ['cross-b', 'cross-c', 'cross-d', 'cross-a'],
    );

    // الطابور المشترك بلا عميل مستقل عن طابور العميل، وترتيبه مستقل أيضًا.
    final shared = PromotionRewardTemplate.lookupCrossCategoryHold(
      withRest,
      customerId: '',
    );
    expect(shared?.cards.map((card) => card.cardId), ['shared-a']);
  });
}
