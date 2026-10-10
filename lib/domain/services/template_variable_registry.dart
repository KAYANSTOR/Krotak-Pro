/// WP-S2 — سجل واحد لمتغيرات القوالب (المصدر الوحيد للحقيقة في الواجهة والتحقق).
///
/// **حدود مهمة (توافق):** المحرك `OutboundTemplateRenderer` يبقى يمرّر كل
/// المرادفات القديمة كما هي، لأن القوالب المخزّنة قد تحتوي `{CARDS}` أو `%amount`.
/// السجل هنا يُستعمل في: أزرار المتغيرات، أسماء العرض العربية، ومنع التكرار
/// **بعد التطبيع** — ولا يعيد كتابة نص قالب محفوظ.
///
/// الدليل على كل مجموعة: `docs/exec/template-variables-inventory.md` (جرد من الكود).
library;

/// تعريف متغير واحد: مفتاح قانوني + اسم عربي واحد + المرادفات القديمة.
final class TemplateVariableSpec {
  const TemplateVariableSpec({
    required this.key,
    required this.arabicName,
    this.aliases = const <String>{},
    this.note,
  });

  /// المفتاح القانوني (يُكتب في النص عند الإدراج من الواجهة).
  final String key;

  /// اسم العرض العربي الوحيد — لا يُعرض أي كود للمستخدم.
  final String arabicName;

  /// مرادفات قديمة تعمل كما هي (توافق خلفي فقط).
  final Set<String> aliases;

  /// ملاحظة تشغيلية (مثال: متغير معلن بلا مصدر قيمة معتمد).
  final String? note;

  Iterable<String> get allKeys => <String>{key, ...aliases};
}

/// سجل المتغيرات — لا إضافة متغير خارج هذا السجل.
abstract final class TemplateVariableRegistry {
  static const List<TemplateVariableSpec> specs = <TemplateVariableSpec>[
    TemplateVariableSpec(
      key: 'serial',
      arabicName: 'رقم الكرت',
      aliases: {'serial_number', 'CARD_SERIAL', 'CARD_CODE', 'الرقم'},
    ),
    TemplateVariableSpec(
      key: 'secret',
      arabicName: 'الرمز السري',
      aliases: {'code', 'CODE', 'SECRET', 'الرمز'},
    ),
    TemplateVariableSpec(
      key: 'card_value',
      arabicName: 'فئة الكرت',
      aliases: {'CARD_VALUE', 'الفئة'},
    ),
    TemplateVariableSpec(
      key: 'network_name',
      arabicName: 'اسم الشبكة',
      aliases: {'NETWORK_NAME', 'network', 'اسم_المحفظة'},
    ),
    TemplateVariableSpec(
      key: 'customer_phone',
      arabicName: 'رقم العميل',
      aliases: {'phone', 'CUSTOMER_PHONE', 'destination'},
    ),
    TemplateVariableSpec(
      key: 'pos_name',
      arabicName: 'اسم نقطة البيع',
      aliases: {'pos', 'POS_NAME'},
    ),
    TemplateVariableSpec(
      key: 'amount',
      arabicName: 'المبلغ',
      // `SETTLEMENT_AMOUNT` و`reward_value` يُحلّان إلى المبلغ نفسه في
      // `local_pos_auto_settlement_service.dart:188` و
      // `local_promotion_fulfillment_service.dart:277` (D9: الدمج بالدلالة).
      aliases: {'AMOUNT', 'المبلغ', 'SETTLEMENT_AMOUNT', 'reward_value'},
    ),
    TemplateVariableSpec(key: 'total', arabicName: 'الإجمالي', aliases: {'TOTAL'}),
    TemplateVariableSpec(
      key: 'quantity',
      arabicName: 'عدد الكروت',
      aliases: {'QUANTITY', 'QUANTITY_TEXT', 'quantity_text'},
    ),
    TemplateVariableSpec(key: 'cards', arabicName: 'بيانات الكروت', aliases: {'CARDS'}),
    TemplateVariableSpec(key: 'currency', arabicName: 'العملة', aliases: {'CURRENCY'}),
    TemplateVariableSpec(
      key: 'category',
      arabicName: 'اسم الفئة',
      aliases: {'category_name'},
    ),
    TemplateVariableSpec(key: 'count', arabicName: 'العدد'),
    TemplateVariableSpec(
      key: 'remaining',
      arabicName: 'الرصيد المتبقي',
      aliases: {'REMAINING_BALANCE'},
    ),
    TemplateVariableSpec(key: 'identifier', arabicName: 'حساب نقطة البيع'),
    TemplateVariableSpec(key: 'promotion_name', arabicName: 'اسم العرض'),
    TemplateVariableSpec(
      key: 'title',
      arabicName: 'عنوان الكرت',
      note: 'غامض: يُحلّ إلى عنوان الكرت في المعاينة وإلى اسم العرض في الإرسال — يحتاج قراراً',
    ),
    TemplateVariableSpec(key: 'reason', arabicName: 'السبب'),
    TemplateVariableSpec(key: 'balance', arabicName: 'الرصيد'),
    TemplateVariableSpec(key: 'debt', arabicName: 'الدين'),
    TemplateVariableSpec(key: 'paid', arabicName: 'المدفوع'),
    TemplateVariableSpec(key: 'surplus', arabicName: 'الفائض'),
    TemplateVariableSpec(key: 'limit', arabicName: 'سقف الدين'),
    TemplateVariableSpec(key: 'sales', arabicName: 'المبيعات'),
    TemplateVariableSpec(key: 'transfers', arabicName: 'التحويلات'),
    TemplateVariableSpec(
      key: 'notify_phone',
      arabicName: 'رقم إشعار نقطة البيع',
      aliases: {'NOTIFY_PHONE'},
    ),
    TemplateVariableSpec(key: 'pos_id', arabicName: 'معرّف نقطة البيع'),
    TemplateVariableSpec(key: 'customer_name', arabicName: 'اسم العميل'),
    TemplateVariableSpec(
      key: 'first_customer_name',
      arabicName: 'الاسم الأول للعميل',
      aliases: {'اسم_الزبون_الاول'},
    ),
    TemplateVariableSpec(
      key: 'user',
      arabicName: 'المستخدم',
      aliases: {'المستخدم'},
      note: 'هوية الكرت عند التسليم — بلا مصدر معتمد في مسار الإيداع بلا كرت',
    ),
  ];

  static final Map<String, TemplateVariableSpec> _byAnyKey = <String, TemplateVariableSpec>{
    for (final spec in specs)
      for (final key in spec.allKeys) key: spec,
  };

  /// كل المفاتيح القانونية.
  static Set<String> get canonicalKeys =>
      specs.map((spec) => spec.key).toSet();

  static TemplateVariableSpec? specOf(String key) => _byAnyKey[key.trim()];

  static bool isKnown(String key) => specOf(key) != null;

  /// المفتاح القانوني لأي مرادف، أو `null` إن كان غير معروف.
  static String? canonical(String key) => specOf(key)?.key;

  /// الاسم العربي الوحيد — لا يُعاد الكود أبدًا.
  static String arabicName(String key) =>
      specOf(key)?.arabicName ?? 'متغير غير معروف';

  /// التطبيع: المرادفات تصبح المفتاح القانوني، وغير المعروف يبقى كما هو.
  static Set<String> canonicalize(Iterable<String> keys) => keys
      .map((key) => canonical(key) ?? key.trim())
      .where((key) => key.isNotEmpty)
      .toSet();

  /// المتغيرات المكررة **بعد التطبيع** (مثال: `{code}` و`{secret}` في قالب واحد).
  static Set<String> duplicatesIn(Iterable<String> keys) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final key in canonicalize(keys)) {
      if (!seen.add(key)) duplicates.add(key);
    }
    return duplicates;
  }

  /// أزرار المتغيرات في الواجهة: مفتاح قانوني + اسم عربي واحد لكل متغير.
  static List<({String key, String label})> buttons() => specs
      .map((spec) => (key: spec.key, label: spec.arabicName))
      .toList(growable: false);
}
