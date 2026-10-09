import '../entities/wallet.dart';

/// تعريف واحد لمحفظة إيداع معتمدة في المنتج.
///
/// هذا الملف هو المصدر الوحيد لأسماء محافظ الإيداع ومفاتيحها الداخلية وبيانات
/// النقل (SMS/إشعارات) التي تُزرع في التطبيق. لا تُعرَّف محفظة افتراضية في أي
/// مكان آخر، ولا يُخترع أي `Sender ID` غير معتمد.
///
/// `key` هو المفتاح الداخلي الثابت (Jaib/Jawali/MFloos/Floosak/KuraimiLMB/
/// ONE Cash) و`senderId` هو قيمة المرسل الرسمية المعتمدة للمطابقة.
final class WalletSpec {
  const WalletSpec({
    required this.key,
    required this.name,
    required this.nameEn,
    required this.sourceMode,
    this.senderId,
    this.packageName,
    this.autoActivate = true,
  });

  /// المفتاح الداخلي الثابت للمحفظة.
  final String key;

  /// الاسم العربي المعروض للمشغّل.
  final String name;

  /// الاسم التقني/الإنجليزي المرجعي.
  final String nameEn;

  /// طريقة قراءة الإيداعات: SMS أو إشعارات التطبيق.
  final WalletSourceMode sourceMode;

  /// `Sender ID` الرسمي المعتمد — null يعني «غير متوفر بعد» ولا يُخترع بديل.
  final String? senderId;

  /// اسم حزمة أندرويد عند القراءة من الإشعارات.
  final String? packageName;

  /// هل تُفعَّل المحفظة تلقائيًا عند الزرع؟
  ///
  /// تكون false عندما لا يوجد `Sender ID` رسمي: الرسائل لا تُعتمد ماليًا حتى
  /// يُدخل المشغّل الـID الرسمي ويُفعّل المحفظة.
  final bool autoActivate;

  bool get hasOfficialSenderId =>
      senderId != null && senderId!.trim().isNotEmpty;
}

/// قائمة محافظ الإيداع المعتمدة — المرجع الوحيد للزرع.
///
/// المصدر الرسمي: رسالة المالك «تعريف محافظ الإيداع وتحليل الرسائل» ثم التصحيح
/// المعتمد: **قيم `Sender ID` الرسمية هي أسماء المحافظ الإنجليزية نفسها، بنفس
/// حالة الأحرف والمسافات**:
///
/// ```text
/// Jaib · Jawali · MFloos · Floosak · KuraimiLMB · ONE Cash
/// ```
///
/// لا يُخترع أي `Sender ID` آخر، ولا تُقبل أي رسالة لا يطابق مرسلُها إحدى هذه
/// القيم مطابقةً تامة (بلا مطابقة جزئية ولا اختلاف في حالة الأحرف أو المسافات).
abstract final class DefaultWalletSpecs {
  /// جيب — Jaib.
  static const jaib = WalletSpec(
    key: 'Jaib',
    name: 'جيب',
    nameEn: 'Jaib',
    senderId: 'Jaib',
    sourceMode: WalletSourceMode.notification,
    packageName: 'com.ahd.jaib',
  );

  /// جوالي — Jawali.
  static const jawali = WalletSpec(
    key: 'Jawali',
    name: 'جوالي',
    nameEn: 'Jawali',
    senderId: 'Jawali',
    sourceMode: WalletSourceMode.sms,
    packageName: 'com.wecash.jawali',
  );

  /// أم فلوس — MFloos.
  static const mfloos = WalletSpec(
    key: 'MFloos',
    name: 'أم فلوس',
    nameEn: 'MFloos',
    senderId: 'MFloos',
    sourceMode: WalletSourceMode.sms,
  );

  /// فلوسك — Floosak.
  static const floosak = WalletSpec(
    key: 'Floosak',
    name: 'فلوسك',
    nameEn: 'Floosak',
    senderId: 'Floosak',
    sourceMode: WalletSourceMode.sms,
    packageName: 'co.ysys.floosak',
  );

  /// الكريمي — KuraimiLMB.
  static const kuraimi = WalletSpec(
    key: 'KuraimiLMB',
    name: 'الكريمي',
    nameEn: 'KuraimiLMB',
    senderId: 'KuraimiLMB',
    sourceMode: WalletSourceMode.sms,
  );

  /// ون كاش — ONE Cash.
  static const oneCash = WalletSpec(
    key: 'ONE Cash',
    name: 'ون كاش',
    nameEn: 'ONE Cash',
    senderId: 'ONE Cash',
    sourceMode: WalletSourceMode.sms,
    packageName: 'com.one.onecustomer',
  );

  /// الترتيب المعتمد في متطلبات المالك.
  static const List<WalletSpec> all = <WalletSpec>[
    jaib,
    jawali,
    mfloos,
    floosak,
    kuraimi,
    oneCash,
  ];

  /// قيم `Sender ID` الرسمية كما هي — مرجع مطابقة مصدر الرسالة.
  static List<String> get officialSenderIds =>
      all.map((spec) => spec.senderId!).toList(growable: false);

  static WalletSpec? byKey(String key) {
    for (final spec in all) {
      if (spec.key == key) return spec;
    }
    return null;
  }

  /// مطابقة مصدر رسالة بقيمة `Sender ID` رسمية — تامة، حسّاسة لحالة الأحرف
  /// والمسافات، وبلا أي مطابقة جزئية.
  static bool matchesOfficialSenderId(String rawSource) {
    final source = rawSource.trim();
    if (source.isEmpty) return false;
    for (final spec in all) {
      if (spec.senderId == source) return true;
    }
    return false;
  }

  /// المحفظة التي يخصّها [rawSource]، أو null إن لم تطابق أي قيمة رسمية.
  static WalletSpec? byOfficialSenderId(String rawSource) {
    final source = rawSource.trim();
    for (final spec in all) {
      if (spec.senderId == source) return spec;
    }
    return null;
  }

  /// المحافظ التي تنتظر `Sender ID` رسميًا — قرار مطلوب من المالك.
  static List<WalletSpec> get awaitingOfficialSenderId =>
      all.where((spec) => !spec.hasOfficialSenderId).toList(growable: false);
}
