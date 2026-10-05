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

  /// مدة الحجز القديمة داخل فئة العميل. مرحلة 70 وحدّت كل الطوابير على النافذة العريضة.
  static const probeHoldDuration = wideProbeHoldDuration;

  /// نافذة كل طوابير المعاينة: العميل داخل الفئة، وعبر الفئات، والفئة، والمشترك.
  static const wideProbeHoldDuration = Duration(days: 7);

  /// حجز طابور العميل عبر الفئات.
  static const customerCrossCategoryHoldDuration = wideProbeHoldDuration;

  /// حجز طابور الفئة بلا عميل والطابور المشترك بلا عميل.
  static const categoryHoldDuration = wideProbeHoldDuration;
  static const sharedCrossCategoryHoldDuration = wideProbeHoldDuration;

  /// حجز طابور العميل داخل الفئة الواحدة.
  static const customerCategoryHoldDuration = wideProbeHoldDuration;

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

  /// مفتاح الحجز: الفئة وحدها، أو الفئة مع عميل حتى لا يستهلك عميل حجز غيره.
  static String holdStorageKey(String categoryId, {String? customerId}) {
    final category = categoryId.trim();
    final customer = customerId?.trim() ?? '';
    if (customer.isEmpty) return category;
    return '$category|customer:$customer';
  }

  /// يحفظ حجزاً واحداً لكل فئة، وحجزاً مستقلاً لكل عميل داخل الفئة.
  static String rememberHold(String? raw, RewardProbeHold hold) {
    final next = decodeHoldMap(raw);
    next[holdStorageKey(hold.categoryId, customerId: hold.customerId)] = hold.toJson();
    return jsonEncode(next);
  }

  /// سقف طابور العميل داخل الفئة. مرحلة 70 رفعته إلى سقف الطوابير العريضة.
  static const probeHoldQueueLimit = wideProbeQueueLimit;

  /// سقف كل طوابير المعاينة دون إلغاء السقف بالكامل.
  static const wideProbeQueueLimit = 32;

  /// طابور العميل عبر الفئات.
  static const customerCrossCategoryQueueLimit = wideProbeQueueLimit;

  /// طابور الفئة بلا عميل والطابور المشترك.
  static const categoryQueueLimit = wideProbeQueueLimit;
  static const sharedCrossCategoryQueueLimit = wideProbeQueueLimit;

  /// طابور العميل داخل الفئة الواحدة.
  static const customerCategoryQueueLimit = wideProbeQueueLimit;

  /// طابور بلا عميل يجمع كروت فئات مختلفة. لا يختلط بطوابير العملاء.
  static const crossCategoryHoldKey = '*';

  static String enqueueHold(String? raw, RewardProbeHold hold) {
    final customerQueue = hold.customerId.trim().isNotEmpty;
    final window = customerQueue ? customerCategoryHoldDuration : categoryHoldDuration;
    final limit = customerQueue ? customerCategoryQueueLimit : categoryQueueLimit;
    final existing = lookupHold(raw, hold.categoryId, customerId: hold.customerId);
    if (existing == null || !existing.isActiveAt(hold.expiresAt.subtract(window))) {
      return rememberHold(raw, hold);
    }
    final cards = <RewardProbeHeldCard>[
      for (final card in existing.cards)
        if (card.cardId != hold.cardId) card,
      RewardProbeHeldCard(cardId: hold.cardId, reservationId: hold.reservationId),
    ];
    final capped = cards.length > limit ? cards.sublist(cards.length - limit) : cards;
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: capped.first.cardId,
        reservationId: capped.first.reservationId,
        expiresAt: existing.expiresAt.isAfter(hold.expiresAt)
            ? existing.expiresAt
            : hold.expiresAt,
        customerId: hold.customerId,
        queue: capped,
      ),
    );
  }

  /// يضيف كرتاً لطابور الصرف عبر الفئات. مع عميل لا يختلط بالطابور المشترك.
  static String enqueueCrossCategoryHold(String? raw, RewardProbeHold hold) {
    final customerId = hold.customerId.trim();
    final existing = lookupCrossCategoryHold(
      raw,
      customerId: customerId.isEmpty ? null : customerId,
    );
    final card = RewardProbeHeldCard(
      cardId: hold.cardId,
      reservationId: hold.reservationId,
      categoryId: hold.categoryId,
    );
    final window = customerId.isEmpty
        ? sharedCrossCategoryHoldDuration
        : customerCrossCategoryHoldDuration;
    if (existing == null || !existing.isActiveAt(hold.expiresAt.subtract(window))) {
      return rememberHold(
        raw,
        RewardProbeHold(
          categoryId: crossCategoryHoldKey,
          cardId: card.cardId,
          reservationId: card.reservationId,
          expiresAt: hold.expiresAt,
          customerId: customerId,
          queue: [card],
        ),
      );
    }
    final cards = <RewardProbeHeldCard>[
      for (final item in existing.cards)
        if (item.cardId != card.cardId) item,
      card,
    ];
    final limit = customerId.isEmpty
        ? sharedCrossCategoryQueueLimit
        : customerCrossCategoryQueueLimit;
    final capped = cards.length > limit ? cards.sublist(cards.length - limit) : cards;
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: crossCategoryHoldKey,
        cardId: capped.first.cardId,
        reservationId: capped.first.reservationId,
        expiresAt: existing.expiresAt.isAfter(hold.expiresAt)
            ? existing.expiresAt
            : hold.expiresAt,
        customerId: customerId,
        queue: capped,
      ),
    );
  }

  static RewardProbeHold? lookupCrossCategoryHold(String? raw, {String? customerId}) {
    return lookupHold(raw, crossCategoryHoldKey, customerId: customerId);
  }

  static String clearCrossCategoryHold(String? raw, {String? customerId}) {
    return clearHold(raw, crossCategoryHoldKey, customerId: customerId);
  }

  static String clearHold(String? raw, String categoryId, {String? customerId}) {
    final next = decodeHoldMap(raw);
    next.remove(holdStorageKey(categoryId, customerId: customerId));
    return jsonEncode(next);
  }

  /// يُخرج كرتاً واحداً من الطابور الذي يحمله ويبقي بقية الكروت وموعد الانتهاء.
  /// لا يمس طابوراً آخر، ولا يمسح الطابور كله إلا إذا كان هذا الكرت آخر عنصر.
  static String dropQueuedCard(
    String? raw, {
    required String cardId,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = lookupCrossCategoryHold(raw, customerId: customer);
    if (cross != null && cross.holdsCard(wanted)) {
      return consumeHold(
        raw,
        crossCategoryHoldKey,
        customerId: customer,
        cardId: wanted,
      );
    }
    final map = decodeHoldMap(raw);
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final categoryId = key.split('|customer:').first.trim();
      if (categoryId.isEmpty || entry.value is! Map) continue;
      final hold = RewardProbeHold.fromJson(categoryId, entry.value);
      if (hold == null || !hold.holdsCard(wanted)) continue;
      if (customer.isNotEmpty && hold.customerId.trim() != customer) continue;
      if (customer.isEmpty && hold.customerId.trim().isNotEmpty) continue;
      return consumeHold(
        raw,
        hold.categoryId,
        customerId: hold.customerId,
        cardId: wanted,
      );
    }
    return raw ?? '{}';
  }

  /// يقدّم كرتاً موجوداً ليصبح أول صرف، دون تحرير حجزه أو مس بقية الطابور.
  static String promoteQueuedCard(
    String? raw, {
    required String cardId,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = lookupCrossCategoryHold(raw, customerId: customer);
    if (cross != null && cross.holdsCard(wanted)) {
      return _promoteHold(raw, cross, wanted);
    }
    final map = decodeHoldMap(raw);
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final categoryId = key.split('|customer:').first.trim();
      if (categoryId.isEmpty || entry.value is! Map) continue;
      final hold = RewardProbeHold.fromJson(categoryId, entry.value);
      if (hold == null || !hold.holdsCard(wanted)) continue;
      if (customer.isNotEmpty && hold.customerId.trim() != customer) continue;
      if (customer.isEmpty && hold.customerId.trim().isNotEmpty) continue;
      return _promoteHold(raw, hold, wanted);
    }
    return raw ?? '{}';
  }

  static String _promoteHold(String? raw, RewardProbeHold hold, String cardId) {
    final cards = hold.cards;
    final index = cards.indexWhere((card) => card.cardId == cardId);
    if (index <= 0) return raw ?? '{}';
    final promoted = cards[index];
    final next = <RewardProbeHeldCard>[
      promoted,
      for (final card in cards)
        if (card.cardId != cardId) card,
    ];
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: next.first.cardId,
        reservationId: next.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: next,
      ),
    );
  }

  /// يؤخّر كرتاً موجوداً خطوة واحدة نحو آخر الطابور دون تحرير حجزه.
  static String delayQueuedCard(
    String? raw, {
    required String cardId,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = lookupCrossCategoryHold(raw, customerId: customer);
    if (cross != null && cross.holdsCard(wanted)) {
      return _delayHold(raw, cross, wanted);
    }
    final map = decodeHoldMap(raw);
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final categoryId = key.split('|customer:').first.trim();
      if (categoryId.isEmpty || entry.value is! Map) continue;
      final hold = RewardProbeHold.fromJson(categoryId, entry.value);
      if (hold == null || !hold.holdsCard(wanted)) continue;
      if (customer.isNotEmpty && hold.customerId.trim() != customer) continue;
      if (customer.isEmpty && hold.customerId.trim().isNotEmpty) continue;
      return _delayHold(raw, hold, wanted);
    }
    return raw ?? '{}';
  }

  static String _delayHold(String? raw, RewardProbeHold hold, String cardId) {
    final cards = [...hold.cards];
    final index = cards.indexWhere((card) => card.cardId == cardId);
    if (index < 0 || index >= cards.length - 1) return raw ?? '{}';
    final current = cards[index];
    cards[index] = cards[index + 1];
    cards[index + 1] = current;
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: cards.first.cardId,
        reservationId: cards.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: cards,
      ),
    );
  }

  /// يقدّم كرتاً موجوداً خطوة واحدة نحو رأس الطابور دون تحرير حجزه.
  /// الكرت الذي في الرأس يبقى مكانه. لا يمس طابوراً آخر ولا موعد الانتهاء.
  static String advanceQueuedCard(
    String? raw, {
    required String cardId,
    String? customerId,
  }) {
    final wanted = cardId.trim();
    if (wanted.isEmpty) return raw ?? '{}';
    final customer = customerId?.trim() ?? '';
    final cross = lookupCrossCategoryHold(raw, customerId: customer);
    if (cross != null && cross.holdsCard(wanted)) {
      return _advanceHold(raw, cross, wanted);
    }
    final map = decodeHoldMap(raw);
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final categoryId = key.split('|customer:').first.trim();
      if (categoryId.isEmpty || entry.value is! Map) continue;
      final hold = RewardProbeHold.fromJson(categoryId, entry.value);
      if (hold == null || !hold.holdsCard(wanted)) continue;
      if (customer.isNotEmpty && hold.customerId.trim() != customer) continue;
      if (customer.isEmpty && hold.customerId.trim().isNotEmpty) continue;
      return _advanceHold(raw, hold, wanted);
    }
    return raw ?? '{}';
  }

  static String _advanceHold(String? raw, RewardProbeHold hold, String cardId) {
    final cards = [...hold.cards];
    final index = cards.indexWhere((card) => card.cardId == cardId);
    if (index <= 0) return raw ?? '{}';
    final current = cards[index];
    cards[index] = cards[index - 1];
    cards[index - 1] = current;
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: cards.first.cardId,
        reservationId: cards.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: cards,
      ),
    );
  }

  /// يزيل كرتاً مستهلكاً من الطابور ويبقي بقية كروت العميل.
  static String consumeHold(
    String? raw,
    String categoryId, {
    String? customerId,
    String? cardId,
  }) {
    final hold = lookupHold(raw, categoryId, customerId: customerId);
    if (hold == null) {
      final customer = customerId?.trim() ?? '';
      final wanted = cardId?.trim() ?? '';
      final fromCross = _consumeMatchingCross(
        raw,
        categoryId,
        customerId: customer,
        cardId: wanted,
      );
      if (fromCross != null) return fromCross;
      return clearHold(raw, categoryId, customerId: customerId);
    }
    final wanted = cardId?.trim() ?? '';
    final remaining = <RewardProbeHeldCard>[
      for (final card in hold.cards)
        if (wanted.isNotEmpty && card.cardId != wanted) card,
    ];
    if (wanted.isEmpty || remaining.length == hold.cards.length) {
      final customer = customerId?.trim() ?? '';
      final fromCross = _consumeMatchingCross(
        raw,
        categoryId,
        customerId: customer,
        cardId: wanted,
      );
      if (fromCross != null) return fromCross;
      return clearHold(raw, categoryId, customerId: customerId);
    }
    if (remaining.isEmpty) return clearHold(raw, categoryId, customerId: customerId);
    return rememberHold(
      raw,
      RewardProbeHold(
        categoryId: hold.categoryId,
        cardId: remaining.first.cardId,
        reservationId: remaining.first.reservationId,
        expiresAt: hold.expiresAt,
        customerId: hold.customerId,
        queue: remaining,
      ),
    );
  }

  static RewardProbeHold? lookupHold(
    String? raw,
    String categoryId, {
    String? customerId,
  }) {
    final key = holdStorageKey(categoryId, customerId: customerId);
    final item = decodeHoldMap(raw)[key];
    if (item == null) return null;
    return RewardProbeHold.fromJson(categoryId.trim(), item, customerId: customerId);
  }

  /// حجز العميل داخل الفئة يسبق طابوره عبر الفئات، ثم حجز الفئة، ثم الطابور المشترك.
  static RewardProbeHold? claimHold(
    String? raw,
    String categoryId,
    DateTime now, {
    String? customerId,
  }) {
    final customer = customerId?.trim() ?? '';
    if (customer.isNotEmpty) {
      final personal = lookupHold(raw, categoryId, customerId: customer);
      if (personal != null && personal.isActiveAt(now)) return personal;
      final personalCross = _claimMatchingCross(
        raw,
        categoryId,
        now,
        customerId: customer,
      );
      if (personalCross != null) return personalCross;
    }
    final hold = lookupHold(raw, categoryId);
    if (hold != null && hold.isActiveAt(now)) return hold;
    return _claimMatchingCross(raw, categoryId, now);
  }

  static RewardProbeHold? _claimMatchingCross(
    String? raw,
    String categoryId,
    DateTime now, {
    String? customerId,
  }) {
    final cross = lookupCrossCategoryHold(raw, customerId: customerId);
    if (cross == null || !cross.isActiveAt(now)) return null;
    final matching = [
      for (final card in cross.cards)
        if (card.categoryId == categoryId.trim() || card.categoryId.isEmpty) card,
    ];
    if (matching.isEmpty) return null;
    return RewardProbeHold(
      categoryId: categoryId.trim(),
      cardId: matching.first.cardId,
      reservationId: matching.first.reservationId,
      expiresAt: cross.expiresAt,
      customerId: customerId ?? '',
      queue: matching,
    );
  }

  static String? _consumeMatchingCross(
    String? raw,
    String categoryId, {
    required String customerId,
    required String cardId,
  }) {
    if (categoryId.trim() == crossCategoryHoldKey || cardId.isEmpty) return null;
    if (customerId.isNotEmpty) {
      final personal = lookupCrossCategoryHold(raw, customerId: customerId);
      if (personal != null && personal.holdsCard(cardId)) {
        return consumeHold(
          raw,
          crossCategoryHoldKey,
          customerId: customerId,
          cardId: cardId,
        );
      }
    }
    final cross = lookupCrossCategoryHold(raw);
    if (cross != null && cross.holdsCard(cardId)) {
      return consumeHold(raw, crossCategoryHoldKey, cardId: cardId);
    }
    return null;
  }

  static Map<String, Map<String, Object?>> decodeHoldMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, Object?>>{};
      decoded.forEach((key, value) {
        final categoryId = key.toString().trim();
        if (categoryId.isEmpty || value is! Map) return;
        out[categoryId] = Map<String, Object?>.from(value);
      });
      return out;
    } catch (_) {
      return {};
    }
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
    this.categoryId = '',
  });

  final String cardId;
  final String title;
  final String serial;
  final String secret;
  final String amount;
  final String categoryId;
}

/// حجز كرت معاينة لصرف المكافأة التالي في نفس الفئة. ليس بيعاً ولا قيد دفتر.
class RewardProbeHeldCard {
  const RewardProbeHeldCard({
    required this.cardId,
    required this.reservationId,
    this.categoryId = '',
  });

  final String cardId;
  final String reservationId;
  final String categoryId;

  Map<String, Object?> toJson() => {
        'cardId': cardId,
        'reservationId': reservationId,
        if (categoryId.trim().isNotEmpty) 'categoryId': categoryId.trim(),
      };
}

class RewardProbeHold {
  const RewardProbeHold({
    required this.categoryId,
    required this.cardId,
    required this.reservationId,
    required this.expiresAt,
    this.customerId = '',
    this.queue = const [],
  });

  final String categoryId;
  final String cardId;
  final String reservationId;
  final DateTime expiresAt;

  /// فارغ يعني حجز الفئة لكل العملاء. غير الفارغ يخص عميلاً واحداً.
  final String customerId;

  /// طابور صرف العميل. الفارغ يعني كرت الرأس فقط، للتوافق مع مراحل 62 و63.
  final List<RewardProbeHeldCard> queue;

  List<RewardProbeHeldCard> get cards {
    if (queue.isNotEmpty) return queue;
    if (cardId.trim().isEmpty || reservationId.trim().isEmpty) return const [];
    return [RewardProbeHeldCard(cardId: cardId, reservationId: reservationId)];
  }

  /// ينتهي الحجز عند لحظة [expiresAt] نفسها، فلا يُصرف بعد بلوغها.
  bool isActiveAt(DateTime now) => expiresAt.isAfter(now);

  bool holdsCard(String id) => cards.any((card) => card.cardId == id);

  RewardProbeHeldCard? cardFor(String id) {
    for (final card in cards) {
      if (card.cardId == id) return card;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'cardId': cards.isEmpty ? cardId : cards.first.cardId,
        'reservationId': cards.isEmpty ? reservationId : cards.first.reservationId,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (customerId.trim().isNotEmpty) 'customerId': customerId.trim(),
        if (cards.length > 1 || cards.any((card) => card.categoryId.trim().isNotEmpty))
          'queue': [for (final card in cards) card.toJson()],
      };

  static RewardProbeHold? fromJson(
    String categoryId,
    Map<dynamic, dynamic> json, {
    String? customerId,
  }) {
    final cardId = json['cardId']?.toString().trim() ?? '';
    final reservationId = json['reservationId']?.toString().trim() ?? '';
    final expires = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    final storedCustomer = customerId?.trim().isNotEmpty == true
        ? customerId!.trim()
        : (json['customerId']?.toString().trim() ?? '');
    final queue = <RewardProbeHeldCard>[];
    final rawQueue = json['queue'];
    if (rawQueue is List) {
      for (final item in rawQueue) {
        if (item is! Map) continue;
        final id = item['cardId']?.toString().trim() ?? '';
        final reservation = item['reservationId']?.toString().trim() ?? '';
        if (id.isEmpty || reservation.isEmpty) continue;
        queue.add(
          RewardProbeHeldCard(
            cardId: id,
            reservationId: reservation,
            categoryId: item['categoryId']?.toString().trim() ?? '',
          ),
        );
      }
    }
    if (queue.isEmpty && cardId.isNotEmpty && reservationId.isNotEmpty) {
      queue.add(RewardProbeHeldCard(cardId: cardId, reservationId: reservationId));
    }
    if (categoryId.trim().isEmpty || queue.isEmpty || expires == null) return null;
    return RewardProbeHold(
      categoryId: categoryId,
      cardId: queue.first.cardId,
      reservationId: queue.first.reservationId,
      expiresAt: expires.toUtc(),
      customerId: storedCustomer,
      queue: queue,
    );
  }
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
