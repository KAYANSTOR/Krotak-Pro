import 'package:flutter/material.dart';

import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_app_bar_title.dart';
import '../widgets/net/net_surface_card.dart';

/// يفتح درجة اللون في الوضع الداكن حتى يبقى التباين مقروءًا على الأسطح الداكنة.
Color _tone(BuildContext context, Color color) {
  if (Theme.of(context).brightness != Brightness.dark) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + 0.24).clamp(0.0, 0.82)).toColor();
}

/// مركز المساعدة — مطابقة بصرية ونصية ووظيفية لفيديو المنتج.
///
/// المصدر الوحيد للمحتوى:
/// product-decisions · business-rules · screenshot-spec-appendix · السلوك المنفَّذ.
/// لا وعود بميزات غير منفَّذة.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _showTop = false;
  String _query = '';
  int? _groupFilter;

  static final _groups = <_HelpGroup>[
    _HelpGroup(
      title: 'البدء والصلاحيات',
      accent: const Color(0xFF0D9488),
      items: [
        _HelpItem(
          title: 'تهيئة التشغيل عند أول فتح',
          icon: Icons.verified_user_rounded,
          iconBg: const Color(0xFF0D9488),
          points: const [
            'عند أول تشغيل يظهر طلب الأذونات كورقة سفلية فوق الواجهة (ليست شاشة كاملة).',
            'الخطوات: SMS والهاتف · الإشعارات · جهات الاتصال · قراءة إشعارات المحافظ · البطارية · التشغيل التلقائي (اختياري حسب الجهاز) · حالة الهاتف.',
            'الخطوات الممنوحة مسبقاً تُتخطى تلقائياً. بعد الإكمال تُحفظ الحالة ولا تُعاد إلا إذا نقص متطلب.',
            'من «فحص النظام» يمكن مراجعة الجاهزية وإعادة فتح إعدادات النظام في أي وقت.',
          ],
          tip: 'على أجهزة شاومي/هواوي/أوبو فعّل التشغيل التلقائي يدوياً حتى يعود NET بعد إعادة تشغيل الهاتف.',
        ),
        _HelpItem(
          title: 'فحص النظام والجاهزية',
          icon: Icons.health_and_safety_rounded,
          iconBg: const Color(0xFF0891B2),
          points: const [
            'شاشة فحص النظام تصنّف المتطلبات: حرجة · مستحسنة · اختيارية.',
            'تعكس حالة الأذونات والبطارية والوصول لإشعارات المحافظ من الجهاز فعلياً.',
            'يمكن فتح إعدادات أندرويد مباشرة من كل بند ثم العودة لإعادة الفحص.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'الرسائل والمعالجة',
      accent: const Color(0xFFD97706),
      items: [
        _HelpItem(
          title: 'دورة استقبال ومعالجة SMS',
          icon: Icons.sms_rounded,
          iconBg: const Color(0xFF0D9488),
          points: const [
            'الرسالة تُحفظ أولاً ثم تُحلَّل ثم تُعالَج — لا معالجة قبل الحفظ.',
            'منع التكرار عبر المرجع الخارجي (externalReference) وبصمة الدفع على مستوى التطبيق.',
            'المعالجة التلقائية تعمل أثناء تشغيل التطبيق. عند الإيقاف تُحفظ الرسائل دون إيداع/بيع/إرسال. الخلفية تعتمد على أذونات الجهاز.',
            'مفتاح «مبالغ الفئات فقط»: إن كان المبلغ لا يطابق فئة نشطة تُصبح الرسالة معلّقة للمراجعة بدل الرفض الفوري.',
          ],
        ),
        _HelpItem(
          title: 'الرسائل المعلّقة (قيد التأكيد)',
          icon: Icons.pending_actions_rounded,
          iconBg: const Color(0xFFD97706),
          points: const [
            'تظهر عند تعذر مطابقة المبلغ لفئة نشطة أو عند إيقاف المعالجة التلقائية بعد التحليل.',
            'الحالات: قيد الانتظار · إرسال · فشل بعد 3 محاولات · انتظار تأكيد الشبكة.',
            'الحد الأقصى لإعادة الإرسال التلقائي: 3 محاولات. بعد 15 دقيقة دون تأكيد شبكة تُعاد للطابور.',
            'الإجراءات اليدوية: اعتماد (إيداع + تدقيق) · رفض (أرشيف المرفوضة) · إعادة إرسال.',
          ],
          tip: 'راجع شاشة المعلّقة بانتظام — أي تأخير شبكة أو فئة غير معرّفة يظهر هنا.',
        ),
        _HelpItem(
          title: 'الرسائل المرفوضة وأكواد الرفض',
          icon: Icons.error_outline_rounded,
          iconBg: const Color(0xFFDC2626),
          points: const [
            'كل رفض يحمل كوداً واضحاً (لا مخزون · مرسل غير معروف · مرجع مكرر · مبلغ غير مطابق…).',
            'التبويبات: جديد للمراجعة · أرشيف الرسائل المحلولة (قراءة فقط).',
            'الفلاتر تساعد على عزل فشل الإرسال عن نقص المخزون وعن أخطاء التحليل.',
            'لا تُحذف السجلات المالية المرتبطة؛ التنظيف الذكي يحترم سياسة الاحتفاظ.',
          ],
        ),
        _HelpItem(
          title: 'الاستعادة بعد الإقلاع والخدمة الخلفية',
          icon: Icons.sync_rounded,
          iconBg: const Color(0xFF7C3AED),
          points: const [
            'عند تشغيل الجهاز يحاول BootReceiver استئناف المسار إذا سمح النظام بذلك (OEM وقد يمنع بعد Force-stop).',
            'مفتاح «الرسائل القديمة عند التوقف» يعيد معالجة الرسائل غير المكتملة مع منع التكرار.',
            'عامل التسليم (MessageDeliveryWorker) يعيد محاولة إرسال الكروت الفاشلة لنفس الكرت فقط — لا صرف كرت بديل تلقائياً.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'المخزون والكروت',
      accent: const Color(0xFF059669),
      items: [
        _HelpItem(
          title: 'الفئات والمخزون',
          icon: Icons.category_rounded,
          iconBg: const Color(0xFF059669),
          points: const [
            'كل فئة لها اسم وقيمة اسمية وحالة تفعيل. الفئة غير النشطة لا تُباع.',
            'ورقة إدارة الفئات تعرض عدّادات: متوفر · محجوز · مباع لكل فئة.',
            'شريط النسبة في شاشة الكروت يعكس المخزون الكلي من المستودع الحقيقي.',
          ],
        ),
        _HelpItem(
          title: 'إضافة واستيراد الكروت',
          icon: Icons.cloud_upload_rounded,
          iconBg: const Color(0xFF0891B2),
          points: const [
            'إضافة فردية: سيريال + رمز (أو سيريال فقط حسب الصيغة).',
            'استيراد دفعة من ملف نصي/CSV بصيغتين: سيريال فقط أو سيريال ورمز.',
            'المعاينة تعرض الأخطاء قبل الالتزام — لا استيراد أعمى.',
            'لا يُباع كرت بلا فئة نشطة مطابقة.',
          ],
        ),
        _HelpItem(
          title: 'الحجز والبيع (FIFO)',
          icon: Icons.lock_clock_rounded,
          iconBg: const Color(0xFFD97706),
          points: const [
            'اختيار الكرت المتاح بترتيب السيريال تصاعدياً (FIFO حتمي).',
            'الحجز من المتاح فقط، والبيع من المحجوز فقط. مدة الحجز الافتراضية 5 دقائق.',
            'الحجز المنتهي يعود للمتاح قبل البحث عن كرت جديد.',
            'عند فشل إرسال SMS بعد البيع يُبقى الكرت للعميل ويُعاد الإرسال عبر عامل التسليم — لا كرت ثانٍ تلقائياً.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'الحسابات والبيع',
      accent: const Color(0xFF2563EB),
      items: [
        _HelpItem(
          title: 'حسابات العملاء',
          icon: Icons.people_alt_rounded,
          iconBg: const Color(0xFF2563EB),
          points: const [
            'إنشاء حساب: جوال · اسم · أرقام محافظ اختيارية. رفض المكرر من الخدمة.',
            'الرصيد من الحركات المكتملة فقط (إيداع/مكافأة/سلفة موجبة · بيع/سحب/تسوية سالبة).',
            'يمكن ربط رقم من جهات الاتصال وفتح ملف العميل وتصدير كشف الحساب نصاً أو صورة.',
          ],
        ),
        _HelpItem(
          title: 'البيع المباشر',
          icon: Icons.point_of_sale_rounded,
          iconBg: const Color(0xFF0D9488),
          points: const [
            'بيع من رصيد العميل أو بيع هدية أو بيع لنقطة بيع عبر نفس مسار ManualSaleRunner.',
            'اختيار الرقم من جهات الاتصال يكشف العميل الموجود ويعرض اسمه.',
            'العملية ذرية: حجز → صرف → حركة → سجل بيع → تدقيق.',
            'فشل الرصيد لا يستهلك كرتاً.',
          ],
        ),
        _HelpItem(
          title: 'قوالب رسائل العملاء والعروض والنظام',
          icon: Icons.message_rounded,
          iconBg: const Color(0xFF7C3AED),
          points: const [
            'من الإعدادات: قوالب صادرة بتبويبات عملاء · عروض · نظام · سلفني.',
            'يمكن إنشاء وتعديل وإصلاح القالب مع معاينة حية للمتغيرات.',
            'سلفني موحّد داخل نفس شاشة القوالب (لا شاشة منفصلة).',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'نقاط البيع والعروض وسلفني',
      accent: const Color(0xFF7C3AED),
      items: [
        _HelpItem(
          title: 'نقاط البيع والتسوية',
          icon: Icons.storefront_rounded,
          iconBg: const Color(0xFF7C3AED),
          points: const [
            'إنشاء نقطة بيع: جوال · سقف دين · نسبة · قوالب تحويل مرتبطة تلقائياً عند التهيئة.',
            'كشف التسوية يعرض المستحق والمدفوع وطريقة الدفع (نقداً / محفظة / بنك) مع أيقونة مميزة.',
            'يمكن الوصول لحسابات نقاط البيع من التقارير ومن الإعدادات (مساران منفصلان كما تقرر).',
            'المحفظة أو نقطة البيع المعلّقة تُحظر من المعالجة عبر PaymentSourceGuard.',
          ],
        ),
        _HelpItem(
          title: 'العروض الترويجية',
          icon: Icons.local_offer_rounded,
          iconBg: const Color(0xFFD97706),
          points: const [
            'إنشاء عرض بمعالج 4 خطوات: العنوان · العتبة · المكافأة · المراجعة.',
            'عند بلوغ العتبة تُصرف المكافأة وفق القواعد المنفَّذة (مع إمكانية العكس عند عكس البيع).',
            'التفعيل والإيقاف من قائمة العروض دون حذف السجل التاريخي.',
          ],
        ),
        _HelpItem(
          title: 'سلفني (الكرت المسبق)',
          icon: Icons.card_giftcard_rounded,
          iconBg: const Color(0xFF059669),
          points: const [
            'سلفني يصدر كرتاً للعميل وفق القوالب والقواعد المعتمدة.',
            'عند فشل SMS يبقى الكرت صادراً ويُعاد الإرسال — لا سحب تلقائي للكرت.',
            'قوالب سلفني تُدار من تبويب سلفني داخل شاشة قوالب الرسائل.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'التقارير والعمليات',
      accent: const Color(0xFF0F766E),
      items: [
        _HelpItem(
          title: 'التقارير والمراقبة',
          icon: Icons.insights_rounded,
          iconBg: const Color(0xFF0F766E),
          points: const [
            'الأرقام من OpsReportService فقط — لا بيانات وهمية.',
            'أقسام: رسائل (معلّقة/مرفوضة/فشل) · تقرير مبيعات بالفترة · نقاط البيع · سجل العمليات.',
            'تقرير المبيعات: اليوم · الشهر · فترة مخصصة + تفاصيل حسب الفئات.',
          ],
        ),
        _HelpItem(
          title: 'سجل العمليات',
          icon: Icons.receipt_long_rounded,
          iconBg: const Color(0xFF0891B2),
          points: const [
            'يعرض الحركات المكتملة من الدفتر مع بحث وتصفية.',
            'كل حركة مرتبطة بسجل تدقيق عند الإنشاء.',
            'من اللوحة: الضغط على عملية يفتح ورقة تفاصيل (مبلغ · مرجع · حالة · مشاركة).',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'الإعدادات والصيانة',
      accent: const Color(0xFF475569),
      items: [
        _HelpItem(
          title: 'إعدادات التشغيل الأساسية',
          icon: Icons.tune_rounded,
          iconBg: const Color(0xFF475569),
          points: const [
            'المعالجة التلقائية · مبالغ الفئات فقط · الرسائل القديمة عند التوقف · تنبيه التدخل · سلفني.',
            'اسم الشبكة يظهر في ترويسة اللوحة ويُستخدم في رسائل النظام.',
            'المظهر: فاتح · داكن · تلقائي حسب الجدول (مساءً داكن / صباحاً فاتح).',
            'عتبة انخفاض المخزون وإعدادات الشرائح من شاشات مخصصة في مركز الإعدادات.',
          ],
        ),
        _HelpItem(
          title: 'النسخ الاحتياطي والتنظيف',
          icon: Icons.backup_rounded,
          iconBg: const Color(0xFF0D9488),
          points: const [
            'نسخة محلية مشفّرة AES-GCM بصيغة .krt — كلمة مرور ≥ 4 أحرف.',
            'الاستعادة تستبدل بيانات التطبيق مع الحفاظ الآمن على عداد الترخيص.',
            'التنظيف الذكي يحذف السجلات القديمة وفق سياسة الاحتفاظ ولا يمس إثبات الحركة المالية الجارية.',
          ],
        ),
        _HelpItem(
          title: 'الترخيص والاشتراك',
          icon: Icons.workspace_premium_rounded,
          iconBg: const Color(0xFFD97706),
          points: const [
            'شريط الاشتراك في اللوحة يُقرأ من الترخيص الفعلي عند وجود تاريخ انتهاء.',
            'تجديد الاشتراك من شاشة مخصصة في الإعدادات.',
          ],
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 240;
    if (show != _showTop) setState(() => _showTop = show);
  }

  List<_HelpGroup> get _visible {
    final q = _query.trim().toLowerCase();
    final source = _groupFilter == null
        ? _groups
        : <_HelpGroup>[_groups[_groupFilter!]];
    if (q.isEmpty) return source;
    final out = <_HelpGroup>[];
    for (final g in source) {
      final items = g.items.where((item) {
        if (item.title.toLowerCase().contains(q)) return true;
        if (g.title.toLowerCase().contains(q)) return true;
        for (final p in item.points) {
          if (p.toLowerCase().contains(q)) return true;
        }
        if (item.tip != null && item.tip!.toLowerCase().contains(q)) {
          return true;
        }
        return false;
      }).toList(growable: false);
      if (items.isNotEmpty) {
        out.add(_HelpGroup(title: g.title, accent: g.accent, items: items));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final visible = _visible;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          backgroundColor: palette.surface,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary),
          ),
          title: const NetAppBarTitle(
            icon: Icons.help_center_rounded,
            title: 'مركز المساعدة',
            subtitle: 'دليل التشغيل من السلوك الفعلي',
          ),
          centerTitle: false,
        ),
        floatingActionButton: _showTop
            ? FloatingActionButton.small(
                heroTag: 'help_scroll_top',
                backgroundColor: palette.primary,
                foregroundColor: Colors.white,
                onPressed: () => _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                ),
                child: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.sm,
                NetSpacing.lg,
                NetSpacing.sm,
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث في المواضيع والنقاط…',
                  hintStyle: TextStyle(
                    fontFamily: NetTypography.family,
                    color: palette.textTertiary,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: palette.textTertiary,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            color: palette.textSecondary,
                          ),
                        ),
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.md,
                    vertical: NetSpacing.md,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: NetRadii.smAll,
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: NetRadii.smAll,
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: NetRadii.smAll,
                    borderSide: BorderSide(color: palette.primary, width: 1.4),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: NetSpacing.lg),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      selected: _groupFilter == null,
                      showCheckmark: false,
                      label: Text(
                        'الكل',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: _groupFilter == null
                              ? Colors.white
                              : palette.textPrimary,
                        ),
                      ),
                      selectedColor: palette.primary,
                      backgroundColor: palette.surface,
                      side: BorderSide(
                        color: _groupFilter == null
                            ? palette.primary
                            : palette.border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: NetRadii.pillAll,
                      ),
                      onSelected: (_) => setState(() => _groupFilter = null),
                    ),
                  ),
                  for (var i = 0; i < _groups.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        selected: _groupFilter == i,
                        showCheckmark: false,
                        label: Text(
                          _groups[i].title,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: _groupFilter == i
                                ? Colors.white
                                : palette.textPrimary,
                          ),
                        ),
                        selectedColor: _groups[i].accent,
                        backgroundColor: palette.surface,
                        side: BorderSide(
                          color: _groupFilter == i
                              ? _groups[i].accent
                              : palette.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: NetRadii.pillAll,
                        ),
                        onSelected: (_) => setState(() {
                          _groupFilter = _groupFilter == i ? null : i;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NetSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'لا نتائج مطابقة',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          color: palette.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        NetSpacing.lg,
                        NetSpacing.sm,
                        NetSpacing.lg,
                        96,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, gi) {
                        final group = visible[gi];
                        return _GroupBlock(group: group);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group});

  final _HelpGroup group;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final accent = _tone(context, group.accent);

    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.title,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                '${group.items.length}',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          for (final item in group.items) ...[
            _HelpCard(item: item),
            const SizedBox(height: NetSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _HelpCard extends StatefulWidget {
  const _HelpCard({required this.item});

  final _HelpItem item;

  @override
  State<_HelpCard> createState() => _HelpCardState();
}

class _HelpCardState extends State<_HelpCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final item = widget.item;
    final bg = _tone(context, item.iconBg);

    return NetSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: NetRadii.mdAll,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(NetSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: NetSizes.badge,
                    height: NetSizes.badge,
                    decoration: BoxDecoration(
                      color: bg.withValues(alpha: 0.16),
                      borderRadius: NetRadii.smAll,
                    ),
                    child: Icon(item.icon, color: bg, size: 22),
                  ),
                  const SizedBox(width: NetSpacing.md),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.md,
                NetSpacing.sm,
                NetSpacing.md,
                NetSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < item.points.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: bg.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                color: bg,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.points[i],
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 13.5,
                                height: 1.5,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (item.tip != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: palette.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.tip!,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12.5,
                                height: 1.45,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpGroup {
  const _HelpGroup({
    required this.title,
    required this.accent,
    required this.items,
  });
  final String title;
  final Color accent;
  final List<_HelpItem> items;
}

final class _HelpItem {
  const _HelpItem({
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.points,
    this.tip,
  });
  final String title;
  final IconData icon;
  final Color iconBg;
  final List<String> points;
  final String? tip;
}
