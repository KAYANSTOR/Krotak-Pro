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
}
