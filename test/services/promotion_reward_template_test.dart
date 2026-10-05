import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/domain/services/promotion_reward_template.dart';

void main() {
  test('empty draft falls back so the offer template is never blank', () {
    expect(
      PromotionRewardTemplate.normalize('   ', fallback: 'افتراضي'),
      'افتراضي',
    );
    expect(
      PromotionRewardTemplate.normalize(null, fallback: 'افتراضي'),
      'افتراضي',
    );
  });

  test('typed body is kept after trim', () {
    expect(
      PromotionRewardTemplate.normalize('  مكافأة {title}  ', fallback: 'x'),
      'مكافأة {title}',
    );
  });

  test('unknown placeholders are reported once', () {
    expect(
      PromotionRewardTemplate.unknownPlaceholders(
        '{title} {serial_number} {serial_number} {secret}',
      ),
      ['serial_number'],
    );
  });

  test('per-offer template wins and empty clears back to global', () {
    const global = 'عام {title}';
    const fallback = 'افتراضي';
    expect(
      PromotionRewardTemplate.resolve(
        perOffer: null,
        global: global,
        fallback: fallback,
      ),
      global,
    );
    expect(
      PromotionRewardTemplate.resolve(
        perOffer: '  خاص {serial}  ',
        global: global,
        fallback: fallback,
      ),
      'خاص {serial}',
    );

    final encoded = PromotionRewardTemplate.encodeMap(
      null,
      promotionId: 'p1',
      body: 'خاص {title}',
    );
    expect(PromotionRewardTemplate.lookup(encoded, 'p1'), 'خاص {title}');
    expect(PromotionRewardTemplate.lookup(encoded, 'p2'), isNull);
    final cleared = PromotionRewardTemplate.encodeMap(
      encoded,
      promotionId: 'p1',
      body: '   ',
    );
    expect(PromotionRewardTemplate.lookup(cleared, 'p1'), isNull);
  });

  test('invalid template map does not throw', () {
    expect(PromotionRewardTemplate.decodeMap('{'), isEmpty);
    expect(PromotionRewardTemplate.lookup('not-json', 'p1'), isNull);
  });

  test('per-customer template wins then falls back to the offer', () {
    const offer = 'عرض {title}';
    const global = 'عام {title}';
    expect(
      PromotionRewardTemplate.resolve(
        perCustomer: '  عميل {customer_name}  ',
        perOffer: offer,
        global: global,
        fallback: 'افتراضي',
      ),
      'عميل {customer_name}',
    );
    expect(
      PromotionRewardTemplate.resolve(
        perCustomer: '   ',
        perOffer: offer,
        global: global,
        fallback: 'افتراضي',
      ),
      offer,
    );

    final encoded = PromotionRewardTemplate.encodeCustomerMap(
      null,
      promotionId: 'p1',
      customerId: 'c1',
      body: 'خاص بالعميل',
    );
    expect(
      PromotionRewardTemplate.lookupCustomer(encoded, 'p1', 'c1'),
      'خاص بالعميل',
    );
    expect(PromotionRewardTemplate.lookupCustomer(encoded, 'p1', 'c2'), isNull);
    expect(PromotionRewardTemplate.lookup(encoded, 'p1'), isNull);
    final cleared = PromotionRewardTemplate.encodeCustomerMap(
      encoded,
      promotionId: 'p1',
      customerId: 'c1',
      body: '',
    );
    expect(PromotionRewardTemplate.lookupCustomer(cleared, 'p1', 'c1'), isNull);
  });

  test('global customer template is used only after the offer template', () {
    const offer = 'عرض {title}';
    const global = 'عام {title}';
    expect(
      PromotionRewardTemplate.resolve(
        perCustomer: null,
        perOffer: offer,
        perCustomerGlobal: 'عميل عام {customer_name}',
        global: global,
        fallback: 'افتراضي',
      ),
      offer,
    );
    expect(
      PromotionRewardTemplate.resolve(
        perCustomer: null,
        perOffer: '   ',
        perCustomerGlobal: '  عميل عام {customer_name}  ',
        global: global,
        fallback: 'افتراضي',
      ),
      'عميل عام {customer_name}',
    );
    expect(
      PromotionRewardTemplate.resolve(
        perCustomer: 'داخل العرض',
        perOffer: offer,
        perCustomerGlobal: 'عميل عام',
        global: global,
        fallback: 'افتراضي',
      ),
      'داخل العرض',
    );

    final encoded = PromotionRewardTemplate.encodeGlobalCustomerMap(
      null,
      customerId: 'c1',
      body: 'قالب العميل العام',
    );
    expect(
      PromotionRewardTemplate.lookupGlobalCustomer(encoded, 'c1'),
      'قالب العميل العام',
    );
    expect(PromotionRewardTemplate.lookupGlobalCustomer(encoded, 'c2'), isNull);
    final cleared = PromotionRewardTemplate.encodeGlobalCustomerMap(
      encoded,
      customerId: 'c1',
      body: '',
    );
    expect(PromotionRewardTemplate.lookupGlobalCustomer(cleared, 'c1'), isNull);
  });

  test('preview names the winning layer and substitutes samples', () {
    final resolved = PromotionRewardTemplate.resolveLayer(
      perCustomer: 'خاص {customer_name}',
      perOffer: 'عرض {promotion_name}',
      perCustomerGlobal: 'عام عميل',
      global: 'عام',
      fallback: 'افتراضي',
    );
    expect(resolved.source, PromotionRewardTemplateSource.customerInOffer);
    expect(resolved.sourceLabel, 'تخصيص العميل داخل العرض');
    expect(
      PromotionRewardTemplate.renderPreview(resolved.template),
      'خاص عميل تجريبي',
    );
  });

  test('empty customer layer falls through to the offer in preview', () {
    final resolved = PromotionRewardTemplate.resolveLayer(
      perCustomer: '   ',
      perOffer: 'عرض {reward_value}',
      global: 'عام',
      fallback: 'افتراضي',
    );
    expect(resolved.source, PromotionRewardTemplateSource.offer);
    expect(PromotionRewardTemplate.renderPreview(resolved.template), 'عرض 100');
  });

  test('unknown placeholder stays literal in the preview', () {
    expect(
      PromotionRewardTemplate.renderPreview('كرت {serial_number}'),
      'كرت {serial_number}',
    );
  });

  test('probe body prefixes the preview and rejects an empty template', () {
    final body = PromotionRewardTemplate.probeBody('مكافأة {customer_name}');
    expect(body, isA<Success<String>>());
    final text = (body as Success<String>).value;
    expect(text, startsWith(PromotionRewardTemplate.probePrefix));
    expect(text, contains('عميل تجريبي'));
    expect(text, isNot(contains('{customer_name}')));
    expect(PromotionRewardTemplate.probeBody('   '), isA<Failure<String>>());
  });

  test('probe destination accepts a phone and rejects a name', () {
    final phone = PromotionRewardTemplate.probeDestination('0777123456');
    expect(phone, isA<Success<String>>());
    expect((phone as Success<String>).value, '777123456');
    expect(
      PromotionRewardTemplate.probeDestination('عميل'),
      isA<Failure<String>>(),
    );
  });

  test('probe delivery status matches only the sent request', () {
    final delivered = PromotionRewardTemplate.probeDeliveryStatus(
      requestId: 7,
      eventRequestId: 7,
      delivered: true,
      resultCode: 0,
    );
    expect(delivered, isA<Success<String>>());
    expect((delivered as Success<String>).value, contains('وصلت'));

    final failed = PromotionRewardTemplate.probeDeliveryStatus(
      requestId: 7,
      eventRequestId: 7,
      delivered: false,
      resultCode: 3,
    );
    expect((failed as Success<String>).value, contains('رمز 3'));
    expect(
      PromotionRewardTemplate.probeDeliveryStatus(
        requestId: 7,
        eventRequestId: 8,
        delivered: true,
        resultCode: 0,
      ),
      isA<Failure<String>>(),
    );
    expect(
      PromotionRewardTemplate.probeDeliveryStatus(
        requestId: null,
        eventRequestId: 7,
        delivered: true,
        resultCode: 0,
      ),
      isA<Failure<String>>(),
    );
  });

  test('probe receipt is remembered per scope and unmatched delivery is ignored', () {
    expect(
      PromotionRewardTemplate.probeScope(promotionId: 'p1', customerId: 'c1'),
      'offer:p1|customer:c1',
    );
    expect(PromotionRewardTemplate.probeScope(), 'global');
    const sent = RewardProbeReceipt(
      scope: 'offer:p1',
      to: '777123456',
      requestId: 7,
      state: 'sent',
    );
    final encoded = PromotionRewardTemplate.rememberProbe(null, sent);
    expect(PromotionRewardTemplate.lookupProbe(encoded, 'offer:p1')?.state, 'sent');
    expect(PromotionRewardTemplate.lookupProbe(encoded, 'global'), isNull);

    final other = PromotionRewardTemplate.applyProbeDelivery(
      current: sent,
      eventRequestId: 8,
      delivered: true,
      resultCode: 0,
    );
    expect(other, isA<Failure<RewardProbeReceipt>>());

    final delivered = PromotionRewardTemplate.applyProbeDelivery(
      current: sent,
      eventRequestId: 7,
      delivered: true,
      resultCode: 0,
    );
    expect(delivered, isA<Success<RewardProbeReceipt>>());
    final stored = (delivered as Success<RewardProbeReceipt>).value;
    expect(stored.state, 'delivered');
    expect(stored.label, contains('وصلت'));
    expect(stored.isError, isFalse);

    const untracked = RewardProbeReceipt(
      scope: 'global',
      to: '777123456',
      requestId: null,
      state: 'untracked',
    );
    expect(
      PromotionRewardTemplate.applyProbeDelivery(
        current: untracked,
        eventRequestId: 7,
        delivered: true,
        resultCode: 0,
      ),
      isA<Failure<RewardProbeReceipt>>(),
    );
    expect(PromotionRewardTemplate.lookupProbe('{', 'global'), isNull);
  });

  test('probe receipt stays bound to the sent body', () {
    const sent = RewardProbeReceipt(
      scope: 'global',
      to: '777123456',
      requestId: 4,
      state: 'delivered',
      body: 'رسالة تجريبية\nمكافأة عميل تجريبي',
    );
    final encoded = PromotionRewardTemplate.rememberProbe(null, sent);
    final loaded = PromotionRewardTemplate.lookupProbe(encoded, 'global');
    expect(loaded?.body, sent.body);
    expect(loaded?.labelFor(sent.body), isNot(contains('لنص سابق')));
    expect(loaded?.labelFor('نص آخر'), contains('لنص سابق'));
    expect(loaded?.matchesBody(sent.body), isTrue);

    const legacy = RewardProbeReceipt(
      scope: 'global',
      to: '777123456',
      requestId: 4,
      state: 'delivered',
    );
    expect(legacy.labelFor(sent.body), contains('لنص سابق'));

    final delivered = PromotionRewardTemplate.applyProbeDelivery(
      current: sent,
      eventRequestId: 4,
      delivered: false,
      resultCode: 3,
    );
    expect(
      (delivered as Success<RewardProbeReceipt>).value.body,
      sent.body,
    );
  });

  test('probe can show an available card without reserving it', () {
    const card = RewardProbeCardSnapshot(
      cardId: 'card-1',
      title: 'كرت 200',
      serial: '999111',
      secret: '4455',
      amount: '200.00',
    );
    final values = PromotionRewardTemplate.probeValues(
      card: card,
      promotionName: 'عرض رمضان',
      customerName: 'سالم',
    );
    expect(values['serial'], '999111');
    expect(values['secret'], '4455');
    expect(values['code'], '4455');
    expect(values['amount'], '200.00');
    expect(values['title'], 'كرت 200');
    expect(values['promotion_name'], 'عرض رمضان');
    expect(values['customer_name'], 'سالم');

    final body = PromotionRewardTemplate.probeBody(
      'سري {serial} كود {secret}',
      values: values,
    );
    expect(body, isA<Success<String>>());
    final text = (body as Success<String>).value;
    expect(text, contains(PromotionRewardTemplate.probePrefix));
    expect(text, contains('999111'));
    expect(text, isNot(contains('123456789012')));

    final samples = PromotionRewardTemplate.probeValues();
    expect(samples['serial'], PromotionRewardTemplate.sampleValues['serial']);
  });

  test('probe card selection stays inside available cards', () {
    const first = RewardProbeCardSnapshot(
      cardId: 'card-1',
      title: 'كرت 100',
      serial: '111',
      secret: '1',
      amount: '100.00',
    );
    const second = RewardProbeCardSnapshot(
      cardId: 'card-2',
      title: 'كرت 200',
      serial: '222',
      secret: '2',
      amount: '200.00',
    );
    expect(PromotionRewardTemplate.selectProbeCard(const []), isNull);
    expect(
      PromotionRewardTemplate.selectProbeCard(const [first, second])?.cardId,
      'card-1',
    );
    expect(
      PromotionRewardTemplate.selectProbeCard(
        const [first, second],
        selectedId: 'card-2',
      )?.serial,
      '222',
    );
    expect(
      PromotionRewardTemplate.selectProbeCard(
        const [first, second],
        selectedId: 'sold-or-missing',
      )?.cardId,
      'card-1',
    );
  });

  test('probe hold is claimed only while it is still active', () {
    final expires = DateTime.utc(2026, 10, 5, 6);
    final hold = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-9',
      reservationId: 'res-9',
      expiresAt: expires,
    );
    final encoded = PromotionRewardTemplate.rememberHold(null, hold);
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
      )?.cardId,
      'card-9',
    );
    expect(
      PromotionRewardTemplate.claimHold(encoded, 'cat-1', expires),
      isNull,
    );
    expect(PromotionRewardTemplate.claimHold(encoded, 'cat-2', expires), isNull);
    final cleared = PromotionRewardTemplate.clearHold(encoded, 'cat-1');
    expect(PromotionRewardTemplate.lookupHold(cleared, 'cat-1'), isNull);
    expect(PromotionRewardTemplate.lookupHold('not-json', 'cat-1'), isNull);
  });

  test('customer probe hold does not consume the category hold', () {
    final expires = DateTime.utc(2026, 10, 5, 6);
    final category = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-category',
      reservationId: 'res-category',
      expiresAt: expires,
    );
    final customer = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-customer',
      reservationId: 'res-customer',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final encoded = PromotionRewardTemplate.rememberHold(
      PromotionRewardTemplate.rememberHold(null, category),
      customer,
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-customer',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-2',
      )?.cardId,
      'card-category',
    );
    final cleared = PromotionRewardTemplate.clearHold(
      encoded,
      'cat-1',
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupHold(cleared, 'cat-1', customerId: 'cust-1'),
      isNull,
    );
    expect(PromotionRewardTemplate.lookupHold(cleared, 'cat-1')?.cardId, 'card-category');
  });

  test('customer probe hold queues cards and consumes only the used card', () {
    final expires = DateTime.utc(2026, 10, 5, 6);
    final first = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-a',
      reservationId: 'res-a',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final second = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-b',
      reservationId: 'res-b',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final encoded = PromotionRewardTemplate.enqueueHold(
      PromotionRewardTemplate.enqueueHold(null, first),
      second,
    );
    final claimed = PromotionRewardTemplate.claimHold(
      encoded,
      'cat-1',
      expires.subtract(const Duration(minutes: 1)),
      customerId: 'cust-1',
    );
    expect(claimed?.cardId, 'card-a');
    expect(claimed?.cards.map((card) => card.cardId), ['card-a', 'card-b']);
    final consumed = PromotionRewardTemplate.consumeHold(
      encoded,
      'cat-1',
      customerId: 'cust-1',
      cardId: 'card-a',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        consumed,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-b',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
      ),
      isNull,
    );
  });

  test('category probe hold queues cards without a customer and keeps the customer queue', () {
    final expires = DateTime.utc(2026, 10, 5, 6);
    final first = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-a',
      reservationId: 'res-a',
      expiresAt: expires,
    );
    final second = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-b',
      reservationId: 'res-b',
      expiresAt: expires,
    );
    final customer = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-c',
      reservationId: 'res-c',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final encoded = PromotionRewardTemplate.enqueueHold(
      PromotionRewardTemplate.enqueueHold(
        PromotionRewardTemplate.enqueueHold(null, customer),
        first,
      ),
      second,
    );
    final claimed = PromotionRewardTemplate.claimHold(
      encoded,
      'cat-1',
      expires.subtract(const Duration(minutes: 1)),
    );
    expect(claimed?.cardId, 'card-a');
    expect(claimed?.cards.map((card) => card.cardId), ['card-a', 'card-b']);
    final consumed = PromotionRewardTemplate.consumeHold(
      encoded,
      'cat-1',
      cardId: 'card-a',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        consumed,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
      )?.cardId,
      'card-b',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        consumed,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-c',
    );
    final cleared = PromotionRewardTemplate.clearHold(consumed, 'cat-1');
    expect(
      PromotionRewardTemplate.lookupHold(cleared, 'cat-1'),
      isNull,
    );
    expect(
      PromotionRewardTemplate.lookupHold(cleared, 'cat-1', customerId: 'cust-1')?.cardId,
      'card-c',
    );
  });

  test('customer cross-category queue keeps the wide window beside the in-category queue', () {
    final start = DateTime.utc(2026, 10, 4, 6);
    var encoded;
    for (var i = 0; i < 9; i++) {
      encoded = PromotionRewardTemplate.enqueueCrossCategoryHold(
        encoded,
        RewardProbeHold(
          categoryId: 'cat-${i % 3}',
          cardId: 'card-$i',
          reservationId: 'res-$i',
          expiresAt: start.add(PromotionRewardTemplate.customerCrossCategoryHoldDuration),
          customerId: 'cust-1',
        ),
      );
    }
    final queue = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: 'cust-1',
    );
    expect(queue?.cards.length, 9);
    expect(queue?.cards.first.cardId, 'card-0');
    expect(
      queue?.expiresAt,
      start.add(PromotionRewardTemplate.customerCrossCategoryHoldDuration),
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-0',
        start.add(const Duration(hours: 25)),
        customerId: 'cust-1',
      )?.cardId,
      'card-0',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-0',
        start.add(const Duration(days: 8)),
        customerId: 'cust-1',
      ),
      isNull,
    );
    var sameCategory;
    for (var i = 0; i < 9; i++) {
      sameCategory = PromotionRewardTemplate.enqueueHold(
        sameCategory,
        RewardProbeHold(
          categoryId: 'cat-1',
          cardId: 'same-$i',
          reservationId: 'same-res-$i',
          expiresAt: start.add(PromotionRewardTemplate.probeHoldDuration),
          customerId: 'cust-1',
        ),
      );
    }
    expect(
      PromotionRewardTemplate.lookupHold(
        sameCategory,
        'cat-1',
        customerId: 'cust-1',
      )?.cards.length,
      9,
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(sameCategory, customerId: 'cust-1'),
      isNull,
    );
  });

  test('customer in-category probe queue uses the 32-card 7-day window', () {
    final start = DateTime.utc(2026, 10, 5, 8);
    var encoded;
    for (var i = 0; i < 33; i++) {
      encoded = PromotionRewardTemplate.enqueueHold(
        encoded,
        RewardProbeHold(
          categoryId: 'cat-1',
          cardId: 'card-$i',
          reservationId: 'res-$i',
          expiresAt: start.add(PromotionRewardTemplate.customerCategoryHoldDuration),
          customerId: 'cust-1',
        ),
      );
    }
    final queue = PromotionRewardTemplate.lookupHold(
      encoded,
      'cat-1',
      customerId: 'cust-1',
    );
    expect(queue?.cards.length, PromotionRewardTemplate.customerCategoryQueueLimit);
    expect(queue?.cards.first.cardId, 'card-1');
    expect(queue?.expiresAt, start.add(PromotionRewardTemplate.customerCategoryHoldDuration));
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        start.add(const Duration(days: 6)),
        customerId: 'cust-1',
      )?.cardId,
      'card-1',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        start.add(const Duration(days: 8)),
        customerId: 'cust-1',
      ),
      isNull,
    );
    expect(PromotionRewardTemplate.lookupHold(encoded, 'cat-1'), isNull);
  });

  test('category and shared probe queues use the 32-card 7-day window', () {
    final start = DateTime.utc(2026, 10, 4, 8);
    var category;
    var shared;
    for (var i = 0; i < 33; i++) {
      category = PromotionRewardTemplate.enqueueHold(
        category,
        RewardProbeHold(
          categoryId: 'cat-1',
          cardId: 'cat-$i',
          reservationId: 'cat-res-$i',
          expiresAt: start.add(PromotionRewardTemplate.categoryHoldDuration),
        ),
      );
      shared = PromotionRewardTemplate.enqueueCrossCategoryHold(
        shared,
        RewardProbeHold(
          categoryId: 'cat-$i',
          cardId: 'shared-$i',
          reservationId: 'shared-res-$i',
          expiresAt: start.add(PromotionRewardTemplate.sharedCrossCategoryHoldDuration),
        ),
      );
    }
    final categoryQueue = PromotionRewardTemplate.lookupHold(category, 'cat-1');
    final sharedQueue = PromotionRewardTemplate.lookupCrossCategoryHold(shared);
    expect(categoryQueue?.cards.length, PromotionRewardTemplate.categoryQueueLimit);
    expect(sharedQueue?.cards.length, PromotionRewardTemplate.sharedCrossCategoryQueueLimit);
    expect(categoryQueue?.cards.first.cardId, 'cat-1');
    expect(sharedQueue?.cards.first.cardId, 'shared-1');
    expect(categoryQueue?.expiresAt, start.add(PromotionRewardTemplate.categoryHoldDuration));
    expect(
      sharedQueue?.expiresAt,
      start.add(PromotionRewardTemplate.sharedCrossCategoryHoldDuration),
    );
    expect(
      PromotionRewardTemplate.claimHold(
        shared,
        'cat-1',
        start.add(const Duration(days: 2)),
      )?.cardId,
      'shared-1',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        category,
        'cat-1',
        start.add(const Duration(days: 8)),
      ),
      isNull,
    );
  });

  test('cross-category probe queue keeps other categories and customer queues', () {
    final expires = DateTime.utc(2026, 10, 6, 6);
    final first = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-a',
      reservationId: 'res-a',
      expiresAt: expires,
    );
    final second = RewardProbeHold(
      categoryId: 'cat-2',
      cardId: 'card-b',
      reservationId: 'res-b',
      expiresAt: expires,
    );
    final customer = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-c',
      reservationId: 'res-c',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final encoded = PromotionRewardTemplate.enqueueCrossCategoryHold(
      PromotionRewardTemplate.enqueueCrossCategoryHold(
        PromotionRewardTemplate.enqueueHold(null, customer),
        first,
      ),
      second,
    );
    final queue = PromotionRewardTemplate.lookupCrossCategoryHold(encoded);
    expect(queue?.cards.map((card) => card.cardId), ['card-a', 'card-b']);
    expect(queue?.cards.map((card) => card.categoryId), ['cat-1', 'cat-2']);
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-2',
        expires.subtract(const Duration(minutes: 1)),
      )?.cardId,
      'card-b',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-1',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-c',
    );
    final consumed = PromotionRewardTemplate.consumeHold(
      encoded,
      'cat-2',
      cardId: 'card-b',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(consumed)?.cards.map((card) => card.cardId),
      ['card-a'],
    );
    final cleared = PromotionRewardTemplate.clearCrossCategoryHold(consumed);
    expect(PromotionRewardTemplate.lookupCrossCategoryHold(cleared), isNull);
    expect(
      PromotionRewardTemplate.lookupHold(cleared, 'cat-1', customerId: 'cust-1')?.cardId,
      'card-c',
    );
  });

  test('customer cross-category probe queue stays separate from the shared queue', () {
    final expires = DateTime.utc(2026, 10, 6, 8);
    final shared = RewardProbeHold(
      categoryId: 'cat-2',
      cardId: 'card-shared',
      reservationId: 'res-shared',
      expiresAt: expires,
    );
    final first = RewardProbeHold(
      categoryId: 'cat-1',
      cardId: 'card-a',
      reservationId: 'res-a',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final second = RewardProbeHold(
      categoryId: 'cat-2',
      cardId: 'card-b',
      reservationId: 'res-b',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final sameCategory = RewardProbeHold(
      categoryId: 'cat-2',
      cardId: 'card-same',
      reservationId: 'res-same',
      expiresAt: expires,
      customerId: 'cust-1',
    );
    final encoded = PromotionRewardTemplate.enqueueHold(
      PromotionRewardTemplate.enqueueCrossCategoryHold(
        PromotionRewardTemplate.enqueueCrossCategoryHold(
          PromotionRewardTemplate.enqueueCrossCategoryHold(null, shared),
          first,
        ),
        second,
      ),
      sameCategory,
    );
    final queue = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: 'cust-1',
    );
    expect(queue?.cards.map((card) => card.cardId), ['card-a', 'card-b']);
    expect(queue?.cards.map((card) => card.categoryId), ['cat-1', 'cat-2']);
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(encoded)?.cardId,
      'card-shared',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        encoded,
        'cat-2',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-same',
    );
    final withoutSame = PromotionRewardTemplate.clearHold(
      encoded,
      'cat-2',
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        withoutSame,
        'cat-2',
        expires.subtract(const Duration(minutes: 1)),
        customerId: 'cust-1',
      )?.cardId,
      'card-b',
    );
    expect(
      PromotionRewardTemplate.claimHold(
        withoutSame,
        'cat-2',
        expires.subtract(const Duration(minutes: 1)),
      )?.cardId,
      'card-shared',
    );
    final consumed = PromotionRewardTemplate.consumeHold(
      withoutSame,
      'cat-2',
      customerId: 'cust-1',
      cardId: 'card-b',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(
        consumed,
        customerId: 'cust-1',
      )?.cards.map((card) => card.cardId),
      ['card-a'],
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(consumed)?.cardId,
      'card-shared',
    );
    final cleared = PromotionRewardTemplate.clearCrossCategoryHold(
      consumed,
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(cleared, customerId: 'cust-1'),
      isNull,
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(cleared)?.cardId,
      'card-shared',
    );
  });

  test('dropping one queued card keeps the other queues and expiry', () {
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
    final withSecond = PromotionRewardTemplate.enqueueCrossCategoryHold(
      encoded,
      hold('cross-a', 'cat-9', customerId: 'cust-1'),
    );
    final dropped = PromotionRewardTemplate.dropQueuedCard(
      withSecond,
      cardId: 'cross-b',
      customerId: 'cust-1',
    );
    final customer = PromotionRewardTemplate.lookupCrossCategoryHold(
      dropped,
      customerId: 'cust-1',
    );
    expect(customer?.cards.map((card) => card.cardId), ['cross-a']);
    expect(customer?.expiresAt, expires);
    expect(
      PromotionRewardTemplate.lookupHold(dropped, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(dropped)?.cardId,
      'shared-a',
    );
    final otherCustomer = PromotionRewardTemplate.dropQueuedCard(
      dropped,
      cardId: 'own-a',
    );
    expect(
      PromotionRewardTemplate.lookupHold(otherCustomer, 'cat-1', customerId: 'cust-1')?.cardId,
      'own-a',
    );
    final clearedOwn = PromotionRewardTemplate.dropQueuedCard(
      dropped,
      cardId: 'own-a',
      customerId: 'cust-1',
    );
    expect(
      PromotionRewardTemplate.lookupHold(clearedOwn, 'cat-1', customerId: 'cust-1'),
      isNull,
    );
    expect(
      PromotionRewardTemplate.lookupCrossCategoryHold(clearedOwn, customerId: 'cust-1')?.cardId,
      'cross-a',
    );
  });
}
