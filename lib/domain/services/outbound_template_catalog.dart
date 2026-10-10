import '../entities/setting.dart';
import 'local_advance_service.dart';

/// تصنيف قالب صادر — يحدد التبويب في «الإعدادات ← قوالب الرسائل».
enum OutboundTemplateCategory {
  customers('العملاء', 'رسائل العملاء'),
  offers('العروض', 'رسائل العروض'),
  pos('نقاط البيع', 'نقاط البيع'),
  salafni('سلفني', 'سلفني'),
  system('النظام', 'رسائل النظام');

  const OutboundTemplateCategory(this.label, this.tabLabel);

  /// اسم التصنيف في التقارير/البحث.
  final String label;

  /// عنوان التبويب في شاشة قوالب الرسائل.
  final String tabLabel;

  /// ترتيب التبويبات في الواجهة — ترتيب العرض الوحيد المعتمد.
  static const List<OutboundTemplateCategory> tabOrder = <OutboundTemplateCategory>[
    customers,
    offers,
    system,
    pos,
    salafni,
  ];
}

/// العقد المركزي الواحد لكل قالب رسالة صادر.
///
/// هذا التعريف هو المصدر الوحيد لـ:
/// - الزرع الأولي ([initialBody]) — يُكتب في الإعدادات عند التهيئة فقط.
/// - قائمة المتغيرات المسموحة ([variables]) والمطلوبة ([requiredVariables]).
/// - عنوان القالب وتصنيفه في الواجهة.
/// - التحقق قبل الإرسال ([OutboundTemplateRenderer]).
///
/// لا يجوز تعريف قالب رسالة في أي مكان آخر، ولا يجوز أن يستخدم أي مسار إرسال
/// نصًا افتراضيًا من هذا الملف وقت التشغيل: بعد الزرع يصبح
/// `Settings → Outbound Message Templates` هو المصدر الوحيد للحقيقة.
final class OutboundTemplateDefinition {
  const OutboundTemplateDefinition({
    required this.key,
    required this.title,
    required this.category,
    required this.variables,
    required this.requiredVariables,
    required this.initialBody,
    required this.usage,
  });

  /// مفتاح الإعداد (`SettingKeys.*`).
  final String key;

  /// العنوان المعروض في شاشة قوالب الرسائل.
  final String title;

  final OutboundTemplateCategory category;

  /// كل المتغيرات التي يجوز لهذا القالب استخدامها.
  final Set<String> variables;

  /// المتغيرات التي يجب أن تكون موجودة في القالب نصًّا.
  final Set<String> requiredVariables;

  /// النص الأولي — يُكتب مرة واحدة عند تهيئة المفتاح، وليس بديلًا وقت الإرسال.
  final String initialBody;

  /// وصف مختصر لمسار الاستخدام (يظهر في الواجهة والتوثيق).
  final String usage;
}

/// السجل المركزي لكل قوالب الرسائل الصادرة في المنتج.
abstract final class OutboundTemplateCatalog {
  /// كل قالب صادر يجب أن يوجد هنا مرة واحدة فقط.
  static const List<OutboundTemplateDefinition> definitions =
      <OutboundTemplateDefinition>[
    OutboundTemplateDefinition(
      key: SettingKeys.voucherDeliverySmsTemplate,
      title: 'تسليم كرت للعميل',
      category: OutboundTemplateCategory.customers,
      variables: _voucherVariables,
      requiredVariables: {'code'},
      initialBody: SettingDefaults.voucherDeliverySmsTemplate,
      usage: 'يُرسل للعميل عند صرف كرت (تحويل وارد أو بيع مباشر أو إعادة تسليم).',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posCustomerCardDeliveryTemplate,
      title: 'تسليم كروت طلب نقطة البيع (للعميل)',
      category: OutboundTemplateCategory.customers,
      variables: {
        'NETWORK_NAME',
        'network',
        'network_name',
        'category',
        'category_name',
        'CARD_VALUE',
        'CURRENCY',
        'cards',
        'CARDS',
        'quantity',
        'QUANTITY',
        'QUANTITY_TEXT',
        'quantity_text',
        'serial',
        'code',
        'secret',
        'CODE',
        'SECRET',
        'CARD_CODE',
        'CUSTOMER_PHONE',
        'customer_phone',
        'phone',
      },
      requiredVariables: {'cards'},
      initialBody: SettingDefaults.posCustomerCardDeliveryTemplate,
      usage: 'يُرسل لجوال العميل عند تنفيذ طلب كروت من نقطة بيع.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.customerDebtPaymentTemplate,
      title: 'تأكيد سداد دين العميل',
      category: OutboundTemplateCategory.customers,
      // قرارات المالك §7: القالب يعرض الإيداع والمخصوم للسداد والفائض والرصيد،
      // بنفس متغيرات قالب سداد السلفني حتى لا يوجد مسار سداد بلا قالب مطابق.
      variables: {
        'amount',
        'paid',
        'surplus',
        'balance',
        'CURRENCY',
        'customer_name',
      },
      requiredVariables: {'amount', 'paid', 'surplus', 'balance'},
      initialBody: SettingDefaults.customerDebtPaymentTemplate,
      usage:
          'يُرسل للعميل عند تأكيد سداد دينه من إيداع أو سداد دفتر، ويعرض الإيداع والمخصوم والفائض والرصيد.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posOrderSuccessTemplate,
      title: 'نجاح طلب نقطة البيع (للنقطة)',
      category: OutboundTemplateCategory.pos,
      variables: {
        'POS_NAME',
        'pos',
        'pos_name',
        'pos_id',
        'CUSTOMER_PHONE',
        'customer_phone',
        'phone',
        'destination',
        'CARD_VALUE',
        'category',
        'category_name',
        'CURRENCY',
        'quantity',
        'QUANTITY',
        'QUANTITY_TEXT',
        'quantity_text',
        'AMOUNT',
        'amount',
        'TOTAL',
        'total',
        'NOTIFY_PHONE',
        'notify_phone',
        'NETWORK_NAME',
        'network',
        'network_name',
      },
      requiredVariables: {'QUANTITY_TEXT'},
      initialBody: SettingDefaults.posOrderSuccessTemplate,
      usage: 'يُرسل لرقم إشعار نقطة البيع بعد تنفيذ الطلب بنجاح.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posCustomerSmsTailTemplate,
      title: 'إضافة اسم نقطة البيع في رسائل العميل',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'CURRENCY'},
      requiredVariables: {},
      initialBody: SettingDefaults.posCustomerSmsTailTemplate,
      usage: 'يُلحق بنهاية رسالة العميل عند تنفيذ العملية من نقطة بيع.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posBalanceResponseTemplate,
      title: 'رد رصيد نقطة البيع',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'balance', 'debt', 'CURRENCY'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.posBalanceResponseTemplate,
      usage: 'يُرسل لنقطة البيع ردًّا على طلب كشف الرصيد.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posCreditLimitExceededTemplate,
      title: 'تجاوز سقف دين نقطة البيع',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'limit', 'CURRENCY'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.posCreditLimitExceededTemplate,
      usage: 'يُرسل لنقطة البيع عند رفض طلب لتجاوزه سقف الدين.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posRequestRejectedTemplate,
      title: 'إشعار رفض طلب نقطة البيع',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'reason'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.posRequestRejectedTemplate,
      usage: 'يُرسل لنقطة البيع عند رفض طلبها لأي سبب تشغيلي آخر.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posInstantChargeConfirmTemplate,
      title: 'تأكيد إرسال شحن فوري',
      category: OutboundTemplateCategory.pos,
      variables: {
        'amount',
        'AMOUNT',
        'phone',
        'CUSTOMER_PHONE',
        'customer_phone',
        'CARD_VALUE',
        'CURRENCY',
        'pos',
        'POS_NAME',
      },
      requiredVariables: {'amount', 'phone'},
      initialBody: SettingDefaults.posInstantChargeConfirmTemplate,
      usage: 'يُرسل لنقطة البيع بعد إتمام شحن فوري لعميل.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.dailyPosSummaryTemplate,
      title: 'ملخص العمليات اليومي لنقاط البيع',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'sales', 'transfers', 'balance', 'CURRENCY'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.dailyPosSummaryTemplate,
      usage: 'يُرسل لنقطة البيع مرة واحدة عند إغلاق يوم العمليات.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posSettlementSuccessTemplate,
      title: 'تأكيد تسوية نقطة البيع',
      category: OutboundTemplateCategory.pos,
      variables: {
        'pos',
        'pos_name',
        'POS_NAME',
        'amount',
        'SETTLEMENT_AMOUNT',
        'remaining',
        'REMAINING_BALANCE',
        'identifier',
        'CURRENCY',
      },
      requiredVariables: {'pos', 'amount'},
      initialBody: SettingDefaults.posSettlementSuccessTemplate,
      usage: 'يُرسل لنقطة البيع عند نجاح تسوية حسابها.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posSettlementFailedTemplate,
      title: 'فشل تسوية نقطة البيع',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME', 'reason'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.posSettlementFailedTemplate,
      usage: 'يُرسل لنقطة البيع عند فشل تسوية حسابها.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.posSettlementUnknownTemplate,
      title: 'تسوية غير مؤكدة',
      category: OutboundTemplateCategory.pos,
      variables: {'pos', 'pos_name', 'POS_NAME'},
      requiredVariables: {'pos'},
      initialBody: SettingDefaults.posSettlementUnknownTemplate,
      usage: 'يُرسل لنقطة البيع حين لا يمكن التحقق من نتيجة التسوية.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.promotionRewardSmsTemplate,
      title: 'مكافأة العرض',
      category: OutboundTemplateCategory.offers,
      variables: {
        'title',
        'serial',
        'secret',
        'code',
        'amount',
        'promotion_name',
        'reward_value',
        'customer_name',
      },
      requiredVariables: {'serial'},
      initialBody: SettingDefaults.promotionRewardSmsTemplate,
      usage: 'يُرسل للعميل عند صرف مكافأة عرض.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.salafniAcceptedTemplate,
      title: 'قبول سلفني',
      category: OutboundTemplateCategory.salafni,
      variables: {'amount', 'serial', 'code', 'secret'},
      requiredVariables: {'amount'},
      initialBody: LocalAdvanceService.defaultAccepted,
      usage: 'يُرسل للعميل عند تفعيل سلفني وصرف الكرت.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.salafniRejectedTemplate,
      title: 'رفض سلفني',
      category: OutboundTemplateCategory.salafni,
      variables: {'reason'},
      requiredVariables: {'reason'},
      initialBody: LocalAdvanceService.defaultRejected,
      usage: 'يُرسل للعميل عند تعذّر تنفيذ طلب سلفني.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.salafniSettledTemplate,
      title: 'سداد سلفني',
      category: OutboundTemplateCategory.salafni,
      variables: {'amount', 'paid', 'surplus', 'balance', 'CURRENCY'},
      requiredVariables: {'amount', 'paid', 'surplus', 'balance'},
      initialBody: LocalAdvanceService.defaultSettled,
      usage: 'يُرسل للعميل عند تسجيل سداد (كامل أو جزئي) على سلفناه.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.lowStockAlertTemplate,
      title: 'تنبيه انخفاض مخزون الكروت',
      category: OutboundTemplateCategory.system,
      variables: {'category', 'category_name', 'count', 'CARD_VALUE'},
      requiredVariables: {'category'},
      initialBody: SettingDefaults.lowStockAlertTemplate,
      usage: 'يُرسل للعميل الذي طلب فئة غير متوفرة في المخزون.',
    ),
    // ── قوالب إرسال الكروت حسب نوع العملية (مرحلة A من خطة التطوير) ──
    OutboundTemplateDefinition(
      key: SettingKeys.cardDeliveryCashTemplate,
      title: 'كرت نقدي',
      category: OutboundTemplateCategory.customers,
      variables: _cardDeliveryVariables,
      requiredVariables: _cardDeliveryRequired,
      initialBody: SettingDefaults.cardDeliveryCashTemplate,
      usage: 'يُرسل للعميل عند صرف كرت نقدي.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.cardDeliveryCreditTemplate,
      title: 'كرت آجل',
      category: OutboundTemplateCategory.customers,
      variables: _cardDeliveryVariables,
      requiredVariables: _cardDeliveryRequired,
      initialBody: SettingDefaults.cardDeliveryCreditTemplate,
      usage: 'يُرسل للعميل عند صرف كرت آجل على حسابه.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.cardDeliveryGiftTemplate,
      title: 'كرت هدية',
      category: OutboundTemplateCategory.customers,
      variables: _cardDeliveryVariables,
      requiredVariables: _cardDeliveryRequired,
      initialBody: SettingDefaults.cardDeliveryGiftTemplate,
      usage: 'يُرسل للمستفيد عند صرف كرت هدية.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.salafniCardDeliveryTemplate,
      title: 'كرت سلفني',
      category: OutboundTemplateCategory.salafni,
      variables: _cardDeliveryVariables,
      requiredVariables: _cardDeliveryRequired,
      initialBody: SettingDefaults.salafniCardDeliveryTemplate,
      usage: 'يُرسل للعميل عند صرف كرت سلفني.',
    ),
    OutboundTemplateDefinition(
      key: SettingKeys.depositNoStockTemplate,
      title: 'استلام إيداع بلا كرت متوفر',
      category: OutboundTemplateCategory.system,
      variables: _depositNoStockVariables,
      requiredVariables: _depositNoStockRequired,
      initialBody: SettingDefaults.depositNoStockTemplate,
      usage: 'يُرسل للعميل عند استلام إيداع دون توفر الفئة/الكرت المطابق.',
    ),
  ];

  /// متغيّرات قوالب إرسال الكروت — الأسماء العربية هي المعتمدة في النص،
  /// والأسماء الإنجليزية/aliases للتوافق مع المسارات القديمة.
  static const Set<String> _cardDeliveryRequired = {
    'اسم_المحفظة',
    'الفئة',
    'الرقم',
    'الرمز',
  };

  static const Set<String> _cardDeliveryVariables = {
    'اسم_المحفظة',
    'network_name',
    'NETWORK_NAME',
    'network',
    'الفئة',
    'CARD_VALUE',
    'category',
    'category_name',
    'الرقم',
    'serial',
    'serial_number',
    'CARD_SERIAL',
    'الرمز',
    'code',
    'secret',
    'CARD_CODE',
    'CURRENCY',
  };

  static const Set<String> _depositNoStockRequired = {
    'اسم_الزبون_الاول',
    'المبلغ',
  };

  static const Set<String> _depositNoStockVariables = {
    'اسم_الزبون_الاول',
    'customer_name',
    'المبلغ',
    'amount',
    'AMOUNT',
    'المستخدم',
    'user',
  };

  static const Set<String> _voucherVariables = {
    'serial',
    'serial_number',
    'الرقم',
    'code',
    'secret',
    'الرمز',
    'CARD_CODE',
    'CARD_SERIAL',
    'المستخدم',
    'user',
    'CARD_VALUE',
    'الفئة',
    'NETWORK_NAME',
    'network',
    'network_name',
    'اسم_المحفظة',
    'CURRENCY',
  };

  /// تعريف القالب بمفتاحه، أو null إن لم يكن مسجّلًا (لا يجوز أن يحدث).
  static OutboundTemplateDefinition? byKey(String key) {
    for (final definition in definitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }

  /// المفتاح مسجّل في العقد المركزي؟
  static bool isRegistered(String key) => byKey(key) != null;

  /// النصوص الأولية للزرع — تُكتب فقط للمفاتيح الغائبة عن الإعدادات.
  static Map<String, String> initialBodies() => <String, String>{
        for (final definition in definitions)
          definition.key: definition.initialBody,
      };

  /// المتغيرات المسموحة لمفتاح؛ مجموعة فارغة إن كان المفتاح غير مسجّل.
  static Set<String> variablesOf(String key) =>
      byKey(key)?.variables ?? const <String>{};

  /// قيم تجريبية للمعاينة — لكل متغير في العقد قيمة واحدة، فلا توجد قائمة
  /// يدوية موازية في الواجهة، والمعاينة تمرّ من نفس محرّك الإرسال.
  static const Map<String, String> previewSamples = <String, String>{
    'serial': '1234567',
    'serial_number': '1234567',
    'الرقم': '1234567',
    'code': '987654',
    'secret': '987654',
    'الرمز': '987654',
    'CODE': '987654',
    'SECRET': '987654',
    'CARD_CODE': '1234567',
    'CARD_SERIAL': '1234567',
    'CARD_VALUE': '10',
    'الفئة': '10',
    'CURRENCY': 'ر.ي',
    'NETWORK_NAME': 'kayan',
    'network': 'kayan',
    'network_name': 'kayan',
    'اسم_المحفظة': 'kayan',
    'amount': '1000',
    'AMOUNT': '1000',
    'paid': '500',
    'surplus': '500',
    'balance': '5000',
    'title': 'عرض تجريبي',
    'promotion_name': 'عرض تجريبي',
    'reward_value': '100',
    'customer_name': 'عميل تجريبي',
    'pos': 'الأمل',
    'pos_name': 'الأمل',
    'POS_NAME': 'الأمل',
    'pos_id': 'pos-demo',
    'debt': '0',
    'limit': '50000',
    'sales': '25000',
    'transfers': '3',
    'reason': 'رصيد غير كافٍ',
    'remaining': '0',
    'REMAINING_BALANCE': '0',
    'SETTLEMENT_AMOUNT': '3000',
    'identifier': '777000111',
    'category': '100 ر.ي',
    'category_name': '100 ر.ي',
    'count': '2',
    'quantity': '1',
    'QUANTITY': '1',
    'QUANTITY_TEXT': 'الكرت',
    'quantity_text': 'الكرت',
    'المبلغ': '1000',
    'اسم_الزبون_الاول': 'عميل تجريبي',
    'المستخدم': '1234567',
    'user': '1234567',
    'CUSTOMER_PHONE': '779776919',
    'customer_phone': '779776919',
    'phone': '779776919',
    'NOTIFY_PHONE': '777000111',
    'notify_phone': '777000111',
    'destination': '779776919',
    'TOTAL': '90',
    'total': '90',
    'cards': 'رقم الكرت: 1234567\nالرمز: 987654',
    'CARDS': 'رقم الكرت: 1234567\nالرمز: 987654',
  };

  /// قيم معاينة كل المتغيرات المسموحة للقالب.
  static Map<String, String> previewValuesFor(
    OutboundTemplateDefinition definition,
  ) =>
      <String, String>{
        for (final variable in definition.variables)
          variable: previewSamples[variable] ?? variable,
      };
}
