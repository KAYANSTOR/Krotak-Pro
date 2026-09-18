import 'package:flutter/material.dart';

import '../theme/kayan_palette.dart';

/// مركز المساعدة — مطابقة تصميم فيديو Z Net.
///
/// المصدر الوحيد للمحتوى:
/// product-decisions.md · business-rules.md · السلوك المنفَّذ في Domain.
/// لا محتوى مخترع ولا وعود بميزات غير منفَّذة.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _showTop = false;
  String _query = '';

  static final _groups = <_HelpGroup>[
    _HelpGroup(
      title: 'التقارير والعمليات',
      accent: const Color(0xFF0D9488),
      items: [
        _HelpItem(
          title: 'تقرير المبيعات والمقارنات الزمنية',
          icon: Icons.bar_chart_rounded,
          iconBg: const Color(0xFF0D9488),
          points: const [
            'مصدر البيانات: المبيعات المكتملة فقط من SaleRepository.',
            'الفترات: اليوم / الشهر عبر بطاقات اللوحة، مع ورقة تفاصيل لكل فترة.',
            'الضغط على بطاقة المبيعات يفتح ورقة نصف شاشة بالقائمة والإجمالي.',
            'لا أرقام ثابتة — كل قيمة من المستودع الحقيقي.',
          ],
        ),
        _HelpItem(
          title: 'سجل العمليات الشامل (All Transactions)',
          icon: Icons.receipt_long_rounded,
          iconBg: const Color(0xFF0891B2),
          points: const [
            'سجل العمليات يعرض الحركات المكتملة من الدفتر.',
            'يمكن التصفية والبحث حسب النوع والمرجع والجوال.',
            'كل حركة مرتبطة بسجل تدقيق (Audit) عند الإنشاء.',
            'الصافي والإيداعات والصرف تُحسب من نفس المصدر.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'مركز استرداد العمليات والأخطاء',
      accent: const Color(0xFF059669),
      items: [
        _HelpItem(
          title: 'إدارة الرسائل المعلّقة (قيد التأكيد) وحالات الشبكة',
          icon: Icons.pending_actions_rounded,
          iconBg: const Color(0xFFD97706),
          points: const [
            'مفهوم الرسائل المعلّقة: عند تعذر مطابقة المبلغ لفئة نشطة (أو عند إيقاف المعالجة التلقائية بعد التحليل)، تُحفظ الرسالة لمراجعة يدوية بدل الرفض الفوري.',
            'الحالات المعروضة للمراجعة: parsed (وأحيانًا received) عبر PendingMessageReviewService.',
            'الاسترداد: خدمة الاستعادة تعيد معالجة الرسائل القديمة عند الإقلاع إذا كان المفتاح مفعّلًا، مع منع التكرار بالمرجع الخارجي.',
            'الإجراءات المتاحة: اعتماد (إيداع في الدفتر + Audit) · رفض (نقل لأرشيف المرفوضة) · بحث بالجوال.',
          ],
          tip:
              'متابعة شاشة الرسائل المعلّقة بانتظام يضمن رضا العملاء وسرعة معالجة أي تأخير ناتج عن انقطاع شبكة الهاتف أو عدم تطابق الفئة.',
        ),
        _HelpItem(
          title: 'سجل الرسائل المرفوضة وأكواد الرفض',
          icon: Icons.error_outline_rounded,
          iconBg: const Color(0xFFDC2626),
          points: const [
            'الأرشيف: الرسائل التي رُفضت يدويًا أو فشلت نهائيًا (حالة rejected).',
            'أسباب شائعة: لا مخزون · فشل إرسال الرمز · صيغة لا تطابق قالبًا · رفض يدوي · تعذر تحديد العميل.',
            'الفلاتر: الكل / فشل إرسال / لا مخزون / تكرار / عدم تطابق قالب / أخرى — مع عدّ لكل تصنيف.',
            'شارة «جديد» للرسائل منذ آخر فتح للشاشة (مفتاح last_rejected_messages_viewed_at).',
          ],
        ),
        _HelpItem(
          title: 'الإجراءات السريعة لاسترداد وحل العمليات المرفوضة',
          icon: Icons.build_rounded,
          iconBg: const Color(0xFF16A34A),
          points: const [
            'إعادة المحاولة اليدوية متاحة من شاشة الرسائل الفاشلة حتى بعد استنفاد التلقائي.',
            'سياسة إعادة المحاولة: حد 5 محاولات + exponential backoff (Phase 4).',
            'لا يُستهلك كرت عند فشل الرصيد؛ الحجز يُحرَّر قبل البحث عن كرت جديد.',
            'كل إجراء اعتماد/رفض/إعادة محاولة يُسجَّل في Audit مرتبطًا بالرسالة.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'الخدمة الخلفية والتشغيل التلقائي',
      accent: const Color(0xFF7C3AED),
      items: [
        _HelpItem(
          title: 'تشغيل الخدمة الخلفية والصلاحيات المطلوبة',
          icon: Icons.power_settings_new_rounded,
          iconBg: const Color(0xFF7C3AED),
          points: const [
            'الاستماع للرسائل (حفظ SMS) مستقل عن المعالجة التلقائية التجارية.',
            'إذن SMS وبطارية غير مقيدة مطلوبان لاستقرار الاستقبال على Android.',
            'إشعارات المحافظ تمر عبر NotificationListenerService ثم UnifiedPaymentEventEngine.',
            'بوابات التحقق من الجهاز تُسجَّل من الإعدادات (Phase 12).',
          ],
        ),
        _HelpItem(
          title: 'استرداد الرسائل غير المقروءة والمزامنة الفورية',
          icon: Icons.sync_rounded,
          iconBg: const Color(0xFF6366F1),
          points: const [
            'مفتاح «معالجة الرسائل القديمة عند التوقف» يعيد معالجة الرسائل عند فتح التطبيق.',
            'منع التكرار يعتمد على المرجع الخارجي وبصمة الدفع (PaymentFingerprint).',
            'فشل حفظ الإشعار محليًا يمنع ACK لتجنب فقدان حدث الدفع.',
            'الاستعادة الدورية للفاشلة تعمل بحد أقصى محاولات مع single-flight guard.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'إدارة وتوليد ومخزون الكروت',
      accent: const Color(0xFF2563EB),
      items: [
        _HelpItem(
          title: 'إضافة الكروت يدويًا وبالإدخال النصي السريع',
          icon: Icons.add_box_outlined,
          iconBg: const Color(0xFF2563EB),
          points: const [
            'من شاشة المخزون: فردي (تسلسل + رمز) أو لصق جماعي بصيغة serial,pin.',
            'يُتخطى السطر الفارغ والتعليق (#) ورأس CSV.',
            'التسلسل المكرر داخل الدفعة أو المخزون يُبلَّغ عنه ولا يُدرج مرتين.',
            'لا تُضاف كروت إلى فئة غير نشطة.',
          ],
        ),
        _HelpItem(
          title: 'استيراد الكروت من ملفات (نص/CSV)',
          icon: Icons.upload_file_rounded,
          iconBg: const Color(0xFF0284C7),
          points: const [
            'المسار المعتمد: تحقق مسبق ثم إدخال مجمّع (Phase 7).',
            'تقرير صفوف مرفوضة يظهر بعد الاستيراد.',
            'التقدم في الشاشة حقيقي من المستودع وليس وهميًا.',
            'استيراد PDF/Excel الثنائي غير مدمج كمحرك منفصل؛ النص/CSV هو المسار الحالي.',
          ],
        ),
        _HelpItem(
          title: 'الحجز والبيع من المخزون (FIFO)',
          icon: Icons.inventory_2_outlined,
          iconBg: const Color(0xFF0EA5E9),
          points: const [
            'الكرت المتاح يُختار بترتيب الرقم التسلسلي تصاعديًا (FIFO حتمي).',
            'الحجز من available فقط، والبيع من reserved فقط.',
            'مدة الحجز الافتراضية خمس دقائق؛ المنتهي يُعاد إلى available.',
            'عكس البيع يعيد الكرت إلى available ويُسجَّل reversal في الدفتر.',
          ],
        ),
      ],
    ),
    _HelpGroup(
      title: 'الأمان، التراخيص، وإعدادات النظام والصيانة',
      accent: const Color(0xFF4F46E5),
      items: [
        _HelpItem(
          title: 'نظام التراخيص وفترة السماح',
          icon: Icons.verified_user_outlined,
          iconBg: const Color(0xFF4F46E5),
          points: const [
            'الترخيص الحالي محلي عبر LocalLicenseService.',
            'انتهاء الصلاحية يُقيَّم عند قراءة الترخيص.',
            'مسار الترخيص السحابي الحقيقي خارج النطاق الحالي حسب قرارات المنتج.',
            'رسائل البث الإداري لا تستهلك رصيد ترخيص الكروت.',
          ],
        ),
        _HelpItem(
          title: 'النسخ الاحتياطي واستعادة البيانات',
          icon: Icons.cloud_upload_outlined,
          iconBg: const Color(0xFFCA8A04),
          points: const [
            'نسخ احتياطي محلي عبر LocalBackupService.',
            'الاستعادة تعيد البيانات مع الحفاظ على Idempotency للمراجع.',
            'لا أسرار (رموز الكروت الحساسة) تُعرض في السجلات العامة.',
            'عمليات التنظيف لا تحذف بيانات مالية دون تأكيد صريح.',
          ],
        ),
        _HelpItem(
          title: 'خيارات التصفية وإعدادات النظام المتقدمة',
          icon: Icons.tune_rounded,
          iconBg: const Color(0xFF9333EA),
          points: const [
            'المفاتيح الثلاثة: المعالجة التلقائية · مبالغ الفئات فقط · الرسائل القديمة عند التوقف.',
            'اسم الشبكة قابل للتعديل ويظهر في ترويسة اللوحة.',
            'الوضع: نظام الجهاز / فاتح / داكن عبر themeModeNotifier.',
            'إعدادات الشريحة والبطارية والتحقق من الجهاز من شاشات مخصصة.',
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
    final show = _scroll.hasClients && _scroll.offset > 280;
    if (show != _showTop) setState(() => _showTop = show);
  }

  List<_HelpGroup> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    final out = <_HelpGroup>[];
    for (final g in _groups) {
      final items = g.items.where((item) {
        if (item.title.toLowerCase().contains(q)) return true;
        if (g.title.toLowerCase().contains(q)) return true;
        for (final p in item.points) {
          if (p.toLowerCase().contains(q)) return true;
        }
        if (item.tip != null && item.tip!.toLowerCase().contains(q)) return true;
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
    final cs = Theme.of(context).colorScheme;
    final kayan = context.kayan;
    final visible = _visible;

    return Scaffold(
      backgroundColor: kayan.appBackground,
      appBar: AppBar(
        backgroundColor: kayan.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: _searching
            ? IconButton(
                tooltip: 'إلغاء',
                onPressed: () {
                  setState(() {
                    _searching = false;
                    _query = '';
                    _searchCtrl.clear();
                  });
                },
                icon: const Icon(Icons.close),
              )
            : IconButton(
                tooltip: 'بحث',
                onPressed: () => setState(() => _searching = true),
                icon: Icon(Icons.search, color: cs.onSurface),
              ),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 16,
                  color: kayan.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث في مركز المساعدة…',
                  hintStyle: TextStyle(
                    fontFamily: 'Tajawal',
                    color: kayan.textTertiary,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'مركز المساعدة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: kayan.textPrimary,
                    ),
                  ),
                  Text(
                    'دليل الاستخدام والأسئلة الشائعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: kayan.textSecondary,
                    ),
                  ),
                ],
              ),
        actions: [
          if (!_searching)
            IconButton(
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_forward, color: cs.onSurface),
            ),
        ],
      ),
      floatingActionButton: _showTop
          ? FloatingActionButton.small(
              heroTag: 'help_scroll_top',
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              onPressed: () => _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              ),
              child: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
            )
          : null,
      body: visible.isEmpty
          ? Center(
              child: Text(
                'لا نتائج مطابقة',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 15,
                  color: kayan.textSecondary,
                ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: visible.length,
              itemBuilder: (context, gi) {
                final group = visible[gi];
                return Padding(
                  padding: EdgeInsets.only(bottom: gi == visible.length - 1 ? 0 : 20),
                  child: _GroupBlock(group: group),
                );
              },
            ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group});
  final _HelpGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, right: 4, left: 4),
          child: Row(
            children: [
              Text(
                '* ',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: group.accent,
                ),
              ),
              Expanded(
                child: Text(
                  group.title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: group.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...group.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ItemCard(item: item),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final _HelpItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kayan = context.kayan;

    return Material(
      color: kayan.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kayan.border.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: null,
          trailing: Icon(Icons.expand_more, color: kayan.textTertiary),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    height: 1.35,
                    color: kayan.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.iconBg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.iconBg, size: 22),
              ),
            ],
          ),
          children: [
            for (var i = 0; i < item.points.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.points[i],
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13.5,
                          height: 1.5,
                          color: kayan.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (item.tip != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.tip!,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12.5,
                          height: 1.45,
                          color: kayan.textSecondary,
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
    );
  }
}

final class _HelpGroup {
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
