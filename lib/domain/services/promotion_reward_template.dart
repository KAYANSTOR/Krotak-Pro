import 'dart:convert';

import '../../core/result.dart';
import '../phone_normalizer.dart';

/// نص رسالة مكافأة العرض: تطبيع وحفظ المتغيرات المعروفة.
class PromotionRewardTemplate {
  const PromotionRewardTemplate._();

  static const knownPlaceholders = <String>[
    'title',
    'serial',
    'secret',
    'code',
    'amount',
    'promotion_name',
    'reward_value',
    'customer_name',
  ];

  /// النص الفارغ يعود للافتراضي حتى لا يُحفظ قالب بلا رسالة.
  static String normalize(String? raw, {required String fallback}) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? fallback.trim() : trimmed;
  }

  /// العميل داخل العرض، ثم قالب العرض، ثم قالب العميل العام، ثم العام، ثم الافتراضي.
  static String resolve({
    String? perCustomer,
    required String? perOffer,
    String? perCustomerGlobal,
    required String? global,
    required String fallback,
  }) =>
      resolveLayer(
        perCustomer: perCustomer,
        perOffer: perOffer,
        perCustomerGlobal: perCustomerGlobal,
        global: global,
        fallback: fallback,
      ).template;

  /// نفس ترتيب الصرف مع اسم الطبقة الرابحة، حتى تعرض المعاينة مصدر النص.
  static PromotionRewardResolution resolveLayer({
    String? perCustomer,
    required String? perOffer,
    String? perCustomerGlobal,
    required String? global,
    required String fallback,
  }) {
    final customer = perCustomer?.trim() ?? '';
    if (customer.isNotEmpty) {
      return PromotionRewardResolution(
        source: PromotionRewardTemplateSource.customerInOffer,
        template: customer,
      );
    }
    final specific = perOffer?.trim() ?? '';
    if (specific.isNotEmpty) {
      return PromotionRewardResolution(
        source: PromotionRewardTemplateSource.offer,
        template: specific,
      );
    }
    final generalCustomer = perCustomerGlobal?.trim() ?? '';
    if (generalCustomer.isNotEmpty) {
      return PromotionRewardResolution(
        source: PromotionRewardTemplateSource.customerGlobal,
        template: generalCustomer,
      );
    }
    final general = global?.trim() ?? '';
    if (general.isNotEmpty) {
      return PromotionRewardResolution(
        source: PromotionRewardTemplateSource.global,
        template: general,
      );
    }
    return PromotionRewardResolution(
      source: PromotionRewardTemplateSource.fallback,
      template: fallback.trim(),
    );
  }

  static const sampleValues = <String, String>{
    'title': 'كرت 100',
    'serial': '123456789012',
    'secret': '0000',
    'code': '0000',
    'amount': '100',
    'promotion_name': 'عرض تجريبي',
    'reward_value': '100',
    'customer_name': 'عميل تجريبي',
  };

  /// يستبدل المتغيرات المعروفة بقيم تجريبية ويبقي المجهولة كما هي.
  static String renderPreview(String template, {Map<String, String>? values}) {
    final source = values ?? sampleValues;
    var output = template;
    source.forEach((name, value) {
      output = output.replaceAll('{$name}', value);
    });
    return output;
  }

  /// بادئة إلزامية حتى لا تُقرأ الرسالة التجريبية كصرف كرت.
  static const probePrefix =
      'رسالة تجريبية من كروتك — ليست كرتاً صادراً ولا تُخصم من المخزون';

  /// يبني نص الإرسال التجريبي من القالب الظاهر، دون لمس المخزون أو الدفتر.
  static Result<String> probeBody(String template) {
    final rendered = renderPreview(template).trim();
    if (rendered.isEmpty) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_empty',
          message: 'لا يوجد نص لإرساله',
        ),
      );
    }
    return Success('$probePrefix\n$rendered');
  }

  /// يرفض الوجهة إن لم تكن رقماً هاتفياً، ويعيد الشكل المعياري للإرسال.
  static Result<String> probeDestination(String raw) {
    final trimmed = raw.trim();
    if (!PhoneNormalizer.isPhoneLike(trimmed)) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_destination',
          message: 'أدخل رقم هاتف صالحاً للرسالة التجريبية',
        ),
      );
    }
    final canonical = PhoneNormalizer.canonicalize(trimmed);
    final destination =
        (canonical == null || canonical.isEmpty) ? trimmed : canonical;
    return Success(destination);
  }

  static String customerKey(String promotionId, String customerId) =>
      '${promotionId.trim()}|${customerId.trim()}';

  static String? lookupCustomer(
    String? raw,
    String promotionId,
    String customerId,
  ) =>
      lookup(raw, customerKey(promotionId, customerId));

  static String? lookupGlobalCustomer(String? raw, String customerId) =>
      lookup(raw, customerId.trim());

  /// النص الفارغ يحذف قالب العميل العام ويعيده إلى قالب العرض أو العام.
  static String encodeGlobalCustomerMap(
    String? raw, {
    required String customerId,
    required String? body,
  }) =>
      encodeMap(raw, promotionId: customerId.trim(), body: body);

  /// النص الفارغ يحذف تخصيص العميل ويعيد العرض إلى قالب العرض/العام.
  static String encodeCustomerMap(
    String? raw, {
    required String promotionId,
    required String customerId,
    required String? body,
  }) =>
      encodeMap(
        raw,
        promotionId: customerKey(promotionId, customerId),
        body: body,
      );

  static Map<String, String> decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        final id = key.toString().trim();
        final body = value?.toString().trim() ?? '';
        if (id.isEmpty || body.isEmpty) return;
        out[id] = body;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String? lookup(String? raw, String promotionId) {
    final body = decodeMap(raw)[promotionId];
    if (body == null || body.trim().isEmpty) return null;
    return body.trim();
  }

  /// يحدّث خريطة القوالب. النص الفارغ يحذف تخصيص العرض ويعود للقالب العام.
  static String encodeMap(
    String? raw, {
    required String promotionId,
    required String? body,
  }) {
    final next = Map<String, String>.from(decodeMap(raw));
    final trimmed = body?.trim() ?? '';
    if (trimmed.isEmpty) {
      next.remove(promotionId);
    } else {
      next[promotionId] = trimmed;
    }
    return jsonEncode(next);
  }

  /// المتغيرات المكتوبة `{name}` وغير المعروفة لصرف المكافأة.
  static List<String> unknownPlaceholders(String body) {
    final found = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'\{([^{}]+)\}').allMatches(body)) {
      final name = match.group(1)!.trim();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      if (!knownPlaceholders.contains(name)) found.add(name);
    }
    return found;
  }
}

enum PromotionRewardTemplateSource {
  customerInOffer,
  offer,
  customerGlobal,
  global,
  fallback,
}

class PromotionRewardResolution {
  const PromotionRewardResolution({
    required this.source,
    required this.template,
  });

  final PromotionRewardTemplateSource source;
  final String template;

  String get sourceLabel => switch (source) {
        PromotionRewardTemplateSource.customerInOffer =>
          'تخصيص العميل داخل العرض',
        PromotionRewardTemplateSource.offer => 'قالب العرض',
        PromotionRewardTemplateSource.customerGlobal => 'قالب العميل العام',
        PromotionRewardTemplateSource.global => 'القالب العام',
        PromotionRewardTemplateSource.fallback => 'النص الافتراضي',
      };
}
