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

  /// يختار كرت المعاينة من المتاح فقط. المعرّف المفقود أو غير المتاح يعود لأول كرت، بلا حجز.
  static RewardProbeCardSnapshot? selectProbeCard(
    List<RewardProbeCardSnapshot> available, {
    String? selectedId,
  }) {
    if (available.isEmpty) return null;
    final wanted = selectedId?.trim() ?? '';
    if (wanted.isNotEmpty) {
      for (final card in available) {
        if (card.cardId == wanted) return card;
      }
    }
    return available.first;
  }

  /// قيم المعاينة. الكرت المتاح يستبدل حقول الكرت فقط، بلا حجز أو خصم.
  static Map<String, String> probeValues({
    RewardProbeCardSnapshot? card,
    String? promotionName,
    String? customerName,
  }) {
    final values = Map<String, String>.from(sampleValues);
    final offer = promotionName?.trim() ?? '';
    if (offer.isNotEmpty) {
      values['promotion_name'] = offer;
      values['title'] = offer;
    }
    final customer = customerName?.trim() ?? '';
    if (customer.isNotEmpty) values['customer_name'] = customer;
    if (card != null) {
      values['title'] = card.title;
      values['serial'] = card.serial;
      values['secret'] = card.secret;
      values['code'] = card.secret;
      values['amount'] = card.amount;
    }
    return values;
  }

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
  static Result<String> probeBody(
    String template, {
    Map<String, String>? values,
  }) {
    final rendered = renderPreview(template, values: values).trim();
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

  /// يربط تقرير الناقل بالطلب التجريبي فقط. التقرير غير المطابق يُرفض ولا يُعرض.
  static Result<String> probeDeliveryStatus({
    required int? requestId,
    required int eventRequestId,
    required bool delivered,
    required int resultCode,
  }) {
    if (requestId == null) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_delivery_untracked',
          message: 'أُرسلت الرسالة للشبكة، وتقرير التسليم غير مربوط بمعرّف طلب',
        ),
      );
    }
    if (eventRequestId != requestId) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_delivery_unmatched',
          message: 'تقرير التسليم لا يخص هذه الرسالة التجريبية',
        ),
      );
    }
    if (delivered) {
      return const Success('وصلت الرسالة التجريبية إلى الجهاز');
    }
    return Success('لم تصل الرسالة التجريبية (رمز $resultCode)');
  }

  /// نطاق الإيصال: تخصيص العميل داخل العرض، ثم العميل العام، ثم العرض، ثم العام.
  static String probeScope({String? promotionId, String? customerId}) {
    final offer = promotionId?.trim() ?? '';
    final customer = customerId?.trim() ?? '';
    if (offer.isNotEmpty && customer.isNotEmpty) {
      return 'offer:$offer|customer:$customer';
    }
    if (customer.isNotEmpty) return 'customer:$customer';
    if (offer.isNotEmpty) return 'offer:$offer';
    return 'global';
  }

  /// يحفظ آخر إيصال تجريبي لهذا النطاق فقط. لا قيد دفتر ولا كرت مخزون.
  static String rememberProbe(String? raw, RewardProbeReceipt receipt) {
    final next = decodeProbeMap(raw);
    next[receipt.scope] = receipt.toJson();
    return jsonEncode(next);
  }

  static RewardProbeReceipt? lookupProbe(String? raw, String scope) {
    final item = decodeProbeMap(raw)[scope];
    if (item == null) return null;
    return RewardProbeReceipt.fromJson(scope, item);
  }

  static Map<String, Map<String, Object?>> decodeProbeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, Object?>>{};
      decoded.forEach((key, value) {
        final scope = key.toString().trim();
        if (scope.isEmpty || value is! Map) return;
        out[scope] = Map<String, Object?>.from(value);
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// يحدّث الإيصال المحفوظ فقط إذا طابق معرّف الطلب. الغياب لا يُرقّى إلى تسليم.
  static Result<RewardProbeReceipt> applyProbeDelivery({
    required RewardProbeReceipt? current,
    required int eventRequestId,
    required bool delivered,
    required int resultCode,
  }) {
    if (current == null || current.requestId == null) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_delivery_untracked',
          message: 'أُرسلت الرسالة للشبكة، وتقرير التسليم غير مربوط بمعرّف طلب',
        ),
      );
    }
    if (current.requestId != eventRequestId) {
      return const Failure(
        AppFailure(
          code: 'reward_probe_delivery_unmatched',
          message: 'تقرير التسليم لا يخص هذه الرسالة التجريبية',
        ),
      );
    }
    return Success(
      current.copyWith(
        state: delivered ? 'delivered' : 'failed',
        resultCode: resultCode,
      ),
    );
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

/// آخر نتيجة رسالة تجريبية لنطاق قالب واحد. ليست حركة مالية.
class RewardProbeCardSnapshot {
  const RewardProbeCardSnapshot({
    required this.cardId,
    required this.title,
    required this.serial,
    required this.secret,
    required this.amount,
  });

  final String cardId;
  final String title;
  final String serial;
  final String secret;
  final String amount;
}

class RewardProbeReceipt {
  const RewardProbeReceipt({
    required this.scope,
    required this.to,
    required this.requestId,
    required this.state,
    this.resultCode,
    this.body = '',
  });

  final String scope;
  final String to;
  final int? requestId;
  final String state;
  final int? resultCode;

  /// نص الإرسال التجريبي كما أُرسل. فارغ في الإيصالات الأقدم من مرحلة 59.
  final String body;

  bool get isError => state == 'failed' || state == 'untracked';

  String get label {
    switch (state) {
      case 'delivered':
        return 'وصلت الرسالة التجريبية إلى الجهاز';
      case 'failed':
        return 'لم تصل الرسالة التجريبية (رمز ${resultCode ?? '-'})';
      case 'untracked':
        return 'أُرسلت الرسالة للشبكة، وتقرير التسليم غير مربوط بمعرّف طلب';
      default:
        return 'أُرسلت الرسالة التجريبية إلى $to. بانتظار تقرير شركة الاتصالات';
    }
  }

  /// الإيصال يخص النص المرسل فقط. مسودة مختلفة أو إيصال بلا نص لا يُعرض كنتيجة الحالية.
  String labelFor(String? currentBody) {
    final current = currentBody?.trim() ?? '';
    if (body.isEmpty || current.isEmpty || body != current) {
      return 'لنص سابق — $label';
    }
    return label;
  }

  bool matchesBody(String? currentBody) {
    final current = currentBody?.trim() ?? '';
    return body.isNotEmpty && current.isNotEmpty && body == current;
  }

  RewardProbeReceipt copyWith({String? state, int? resultCode}) =>
      RewardProbeReceipt(
        scope: scope,
        to: to,
        requestId: requestId,
        state: state ?? this.state,
        resultCode: resultCode ?? this.resultCode,
        body: body,
      );

  Map<String, Object?> toJson() => {
        'to': to,
        'requestId': requestId,
        'state': state,
        'resultCode': resultCode,
        'body': body,
      };

  static RewardProbeReceipt? fromJson(String scope, Map<dynamic, dynamic> json) {
    final to = json['to']?.toString().trim() ?? '';
    final state = json['state']?.toString().trim() ?? '';
    if (to.isEmpty || state.isEmpty) return null;
    final rawId = json['requestId'];
    final requestId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    final rawCode = json['resultCode'];
    final resultCode = rawCode is int ? rawCode : int.tryParse('${rawCode ?? ''}');
    return RewardProbeReceipt(
      scope: scope,
      to: to,
      requestId: requestId,
      state: state,
      resultCode: resultCode,
      body: json['body']?.toString() ?? '',
    );
  }
}
