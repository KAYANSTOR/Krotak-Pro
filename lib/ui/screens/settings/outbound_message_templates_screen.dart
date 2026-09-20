import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/services/default_outbound_templates_seeder.dart';
import '../../../domain/services/local_advance_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/async_views.dart';

/// قوالب رسائل العملاء / العروض / النظام / سلفني — مطابقة فيديو المنتج.
class OutboundMessageTemplatesScreen extends StatefulWidget {
  const OutboundMessageTemplatesScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<OutboundMessageTemplatesScreen> createState() =>
      _OutboundMessageTemplatesScreenState();
}

class _Tpl {
  const _Tpl(
    this.keyName,
    this.title,
    this.fallback,
    this.vars, {
    this.isCustom = false,
  });
  final String keyName;
  final String title;
  final String fallback;
  final List<String> vars;

  /// قالب أنشأه المشغّل بنفسه (لا قالب نظام) — قابل للحذف.
  final bool isCustom;
}

class _TabDef {
  const _TabDef(this.label, this.items);
  final String label;
  final List<_Tpl> items;
}

class _OutboundMessageTemplatesScreenState
    extends State<OutboundMessageTemplatesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  final Map<String, String> _values = {};

  /// القوالب المخصّصة التي أنشأها المشغّل — مفهرسة برقم التبويب.
  final Map<int, List<_Tpl>> _custom = <int, List<_Tpl>>{};

  static final _tabsData = <_TabDef>[
    _TabDef('رسائل العملاء', [
      _Tpl(SettingKeys.voucherDeliverySmsTemplate, 'تسليم الكرت للعميل', SettingDefaults.voucherDeliverySmsTemplate, const ['serial', 'code', 'CARD_CODE', 'CARD_VALUE', 'CURRENCY', 'NETWORK_NAME']),
      _Tpl(SettingKeys.customerDebtPaymentTemplate, 'تأكيد سداد دين العميل', SettingDefaults.customerDebtPaymentTemplate, const ['amount', 'balance', 'CURRENCY']),
    ]),
    _TabDef('رسائل العروض', [
      _Tpl(SettingKeys.promotionRewardSmsTemplate, 'مكافأة العرض', SettingDefaults.promotionRewardSmsTemplate, const ['title', 'serial', 'secret', 'promotion_name', 'reward_value']),
    ]),
    _TabDef('رسائل النظام', [
      _Tpl(SettingKeys.lowStockAlertTemplate, 'تنبيه انخفاض مخزون الكروت', SettingDefaults.lowStockAlertTemplate, const ['category', 'count']),
    ]),
    _TabDef('نقاط البيع', [
      _Tpl(
        SettingKeys.posCustomerCardDeliveryTemplate,
        'تسليم كرت لعميل نقطة البيع',
        SettingDefaults.posCustomerCardDeliveryTemplate,
        const [
          'NETWORK_NAME',
          'CARD_VALUE',
          'CURRENCY',
          'serial',
          'code',
          'secret',
          'cards',
          'QUANTITY_TEXT',
          'CUSTOMER_PHONE',
          'category',
        ],
      ),
      _Tpl(
        SettingKeys.posOrderSuccessTemplate,
        'تأكيد تنفيذ طلب نقطة البيع',
        SettingDefaults.posOrderSuccessTemplate,
        const [
          'POS_NAME',
          'CUSTOMER_PHONE',
          'CARD_VALUE',
          'CURRENCY',
          'QUANTITY_TEXT',
          'TOTAL',
          'AMOUNT',
          'NETWORK_NAME',
          'category',
        ],
      ),
      _Tpl(SettingKeys.posBalanceResponseTemplate, 'رد رصيد نقطة البيع', SettingDefaults.posBalanceResponseTemplate, const ['pos', 'balance', 'debt']),
      _Tpl(SettingKeys.posCreditLimitExceededTemplate, 'تجاوز سقف دين نقطة البيع', SettingDefaults.posCreditLimitExceededTemplate, const ['pos', 'limit']),
      _Tpl(SettingKeys.dailyPosSummaryTemplate, 'ملخص العمليات اليومي لنقاط البيع', SettingDefaults.dailyPosSummaryTemplate, const ['pos', 'sales', 'transfers', 'balance']),
      _Tpl(SettingKeys.posSettlementSuccessTemplate, 'تأكيد تسوية حساب نقاط البيع', SettingDefaults.posSettlementSuccessTemplate, const ['pos', 'amount', 'SETTLEMENT_AMOUNT', 'REMAINING_BALANCE']),
      _Tpl(SettingKeys.posSettlementFailedTemplate, 'فشل تسوية نقطة البيع', SettingDefaults.posSettlementFailedTemplate, const ['pos', 'reason']),
      _Tpl(SettingKeys.posSettlementUnknownTemplate, 'تسوية غير مؤكدة', SettingDefaults.posSettlementUnknownTemplate, const ['pos']),
      _Tpl(SettingKeys.posRequestRejectedTemplate, 'إشعار رفض طلب نقطة البيع', SettingDefaults.posRequestRejectedTemplate, const ['pos', 'reason']),
      _Tpl(SettingKeys.posCustomerSmsTailTemplate, 'إضافة اسم نقطة البيع في الرسائل', SettingDefaults.posCustomerSmsTailTemplate, const ['pos', 'pos_name', 'CURRENCY']),
    ]),
    _TabDef('سلفني', [
      _Tpl(SettingKeys.salafniAcceptedTemplate, 'قبول سلفني', LocalAdvanceService.defaultAccepted, const ['amount', 'serial', 'code']),
      _Tpl(SettingKeys.salafniRejectedTemplate, 'رفض سلفني', LocalAdvanceService.defaultRejected, const ['reason']),
      _Tpl(SettingKeys.salafniSettledTemplate, 'تسديد سلفني', LocalAdvanceService.defaultSettled, const ['amount', 'remaining']),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.initialTab.clamp(0, _tabsData.length - 1);
    _tabs = TabController(length: _tabsData.length, vsync: this, initialIndex: i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final c = AppScope.of(context);
    await DefaultOutboundTemplatesSeeder(settings: c.settings, clock: c.clock).seedIfNeeded();
    final next = <String, String>{};
    for (final tab in _tabsData) {
      for (final t in tab.items) {
        final r = await c.settings.find(t.keyName);
        next[t.keyName] = (r is Success<AppSetting?> && (r.value?.value.trim().isNotEmpty ?? false)) ? r.value!.value : t.fallback;
      }
    }

    // القوالب المخصّصة — تُقرأ من إعداد واحد وتُوزّع على تبويباتها.
    final custom = <int, List<_Tpl>>{};
    final raw = await c.settings.find(SettingKeys.customOutboundTemplates);
    final payload = raw is Success<AppSetting?> ? raw.value?.value : null;
    if (payload != null && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final id = (entry['id'] as String?)?.trim() ?? '';
            final title = (entry['title'] as String?)?.trim() ?? '';
            if (id.isEmpty || title.isEmpty) continue;
            final tab = (entry['tab'] as num?)?.toInt() ?? 0;
            final index = tab.clamp(0, _tabsData.length - 1);
            final key = _customKey(id);
            final body = (entry['body'] as String?) ?? '';
            next[key] = body;
            (custom[index] ??= <_Tpl>[]).add(
              _Tpl(key, title, body, const ['CARD_CODE', 'CARD_VALUE', 'CURRENCY', 'NETWORK_NAME', 'amount', 'balance', 'pos', 'reason'], isCustom: true),
            );
          }
        }
      } on FormatException {
        // إعداد قديم/تالف — يتم تجاهله ولا يعطّل الشاشة.
      }
    }

    if (!mounted) return;
    setState(() {
      _values..clear()..addAll(next);
      _custom..clear()..addAll(custom);
      _loading = false;
    });
  }

  static String _customKey(String id) => 'custom:$id';

  List<_Tpl> _tabItems(int index) => <_Tpl>[
        ..._tabsData[index].items,
        ...?_custom[index],
      ];

  /// حفظ قالب جديد فعلياً: يُضاف للسجل ويُحفظ نصه، فلا يضيع كما كان سابقاً.
  Future<bool> _createCustom({
    required String title,
    required String body,
    required int tabIndex,
  }) async {
    final c = AppScope.of(context);
    final id = c.ids.next('tpl').replaceAll(':', '-');
    final entry = <String, Object?>{
      'id': id,
      'title': title,
      'tab': tabIndex,
      'body': body,
    };

    final existing = await c.settings.find(SettingKeys.customOutboundTemplates);
    final raw = existing is Success<AppSetting?> ? existing.value?.value : null;
    final list = <Map<String, Object?>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded.whereType<Map>().map((e) => Map<String, Object?>.from(e)));
        }
      } on FormatException {
        // نتجاهل السجل التالف ونبدأ بقائمة جديدة.
      }
    }
    list.add(entry);

    final bodySaved = await c.settings.save(
      AppSetting(key: _customKey(id), value: body, updatedAt: c.clock.now()),
    );
    if (bodySaved is Failure) {
      if (mounted) _snack(bodySaved.error.message);
      return false;
    }
    final saved = await c.settings.save(
      AppSetting(
        key: SettingKeys.customOutboundTemplates,
        value: jsonEncode(list),
        updatedAt: c.clock.now(),
      ),
    );
    if (saved is Failure) {
      if (mounted) _snack(saved.error.message);
      return false;
    }
    return true;
  }

  Future<void> _deleteCustom(_Tpl t) async {
    final c = AppScope.of(context);
    final existing = await c.settings.find(SettingKeys.customOutboundTemplates);
    final raw = existing is Success<AppSetting?> ? existing.value?.value : null;
    final list = <Map<String, Object?>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded.whereType<Map>().map((e) => Map<String, Object?>.from(e)));
        }
      } on FormatException {
        // لا شيء لحذفه من سجل تالف.
      }
    }
    list.removeWhere((e) => _customKey((e['id'] as String?) ?? '') == t.keyName);
    await c.settings.save(
      AppSetting(
        key: SettingKeys.customOutboundTemplates,
        value: jsonEncode(list),
        updatedAt: c.clock.now(),
      ),
    );
    if (mounted) _snack('تم حذف القالب');
    await _load();
  }

  Future<void> _save(String key, String value) async {
    final c = AppScope.of(context);
    final r = await c.settings.save(AppSetting(key: key, value: value, updatedAt: c.clock.now()));
    if (!mounted) return;
    if (r is Failure) { _snack(r.error.message); return; }
    setState(() => _values[key] = value);
    _snack('تم تحديث القالب بنجاح');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Tajawal'))));
  }

  String _preview(String body) {
    return body
        .replaceAll('{serial}', '1234567').replaceAll('{code}', '987654').replaceAll('{secret}', '987654')
        .replaceAll('{CARD_CODE}', '1234567').replaceAll('{CARD_VALUE}', '10').replaceAll('{CURRENCY}', 'ر.ي')
        .replaceAll('{NETWORK_NAME}', 'kayan').replaceAll('{amount}', '1000').replaceAll('{balance}', '5000')
        .replaceAll('{title}', 'عرض تجريبي').replaceAll('{promotion_name}', 'عرض تجريبي').replaceAll('{reward_value}', '100')
        .replaceAll('{pos}', 'الأمل').replaceAll('{pos_name}', 'الأمل').replaceAll('{debt}', '0').replaceAll('{limit}', '50000')
        .replaceAll('{sales}', '25000').replaceAll('{transfers}', '3').replaceAll('{reason}', 'رصيد غير كافٍ')
        .replaceAll('{remaining}', '0').replaceAll('{category}', '100 ر.ي').replaceAll('{count}', '2')
        .replaceAll('{SETTLEMENT_AMOUNT}', '3000').replaceAll('{REMAINING_BALANCE}', '0')
        .replaceAll('{QUANTITY_TEXT}', 'الكرت').replaceAll('{QUANTITY}', '1').replaceAll('{CUSTOMER_PHONE}', '779776919')
        .replaceAll('{POS_NAME}', 'الأمل').replaceAll('{TOTAL}', '90').replaceAll('{AMOUNT}', '90').replaceAll('{cards}', 'رقم الكرت: 1234567\\nالرمز: 987654');
  }

  Future<void> _edit(_Tpl? item) async {
    final isNew = item == null;
    var tabIndex = _tabs.index.clamp(0, _tabsData.length - 1);
    final nameCtrl = TextEditingController(text: item?.title ?? '');
    final bodyCtrl = TextEditingController(text: item != null ? (_values[item.keyName] ?? item.fallback) : '');
    final vars = item?.vars ?? const ['NETWORK_NAME', 'CARD_VALUE', 'CURRENCY', 'cards', 'CUSTOMER_PHONE', 'POS_NAME', 'QUANTITY_TEXT', 'TOTAL', 'category', 'reason'];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx, setLocal) {
            final inset = MediaQuery.viewInsetsOf(ctx).bottom;
            final body = bodyCtrl.text;
            final chars = body.length;
            final parts = (chars / 70).ceil().clamp(1, 10);
            final palette = KayanPalette.of(ctx);
            return Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92),
                decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 12),
                  Text(isNew ? 'إنشاء قالب رسالة جديد' : 'تعديل قالب رسالة', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 18, color: palette.primary)),
                  const SizedBox(height: 16),
                  Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (isNew) ...[
                      DropdownButtonFormField<int>(
                        value: tabIndex,
                        decoration: InputDecoration(labelText: 'يُضاف إلى', labelStyle: const TextStyle(fontFamily: 'Tajawal'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        items: [
                          for (var i = 0; i < _tabsData.length; i++)
                            DropdownMenuItem(value: i, child: Text(_tabsData[i].label, style: const TextStyle(fontFamily: 'Tajawal'))),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setLocal(() => tabIndex = value);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(controller: nameCtrl, style: const TextStyle(fontFamily: 'Tajawal'), decoration: InputDecoration(labelText: 'اسم القالب', labelStyle: const TextStyle(fontFamily: 'Tajawal'), prefixIcon: const Icon(Icons.title_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    TextField(controller: bodyCtrl, minLines: 4, maxLines: 8, onChanged: (_) => setLocal(() {}), style: const TextStyle(fontFamily: 'Tajawal', height: 1.4), decoration: InputDecoration(labelText: 'نص رسالة الـ SMS', labelStyle: const TextStyle(fontFamily: 'Tajawal'), prefixIcon: const Icon(Icons.sms_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), alignLabelWithHint: true)),
                    const SizedBox(height: 12),
                    const Text('أزرار المساعدة للمتغيرات (اضغط لإدراجها في مكان مؤشر الكتابة):', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final v in vars)
                        ActionChip(label: Text('+'+v, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)), onPressed: () {
                          final t = bodyCtrl.text; final sel = bodyCtrl.selection; final ins = '{'+v+'}';
                          final start = sel.isValid ? sel.start : t.length; final end = sel.isValid ? sel.end : t.length;
                          bodyCtrl.text = t.replaceRange(start, end, ins);
                          bodyCtrl.selection = TextSelection.collapsed(offset: start + ins.length);
                          setLocal(() {});
                        }),
                    ]),
                    const SizedBox(height: 12),
                    Text('حجم الرسالة: '+chars.toString()+' حرف · أجزاء: '+parts.toString()+' · Unicode (UCS-2)', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary)),
                    const SizedBox(height: 12),
                    const Text('معاينة حية للرسالة (Live Preview):', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: palette.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.phone_android_rounded, size: 16, color: palette.textSecondary), const SizedBox(width: 6), Text('شاشة هاتف العميل المستلم', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary))]),
                      const SizedBox(height: 8),
                      Text(body.isEmpty ? '—' : _preview(body), style: const TextStyle(fontFamily: 'Tajawal', height: 1.45)),
                    ])),
                  ]))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')))),
                    Expanded(flex: 2, child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: () async {
                      final b = bodyCtrl.text.trim();
                      if (b.isEmpty) { _snack('لا يمكن ترك نص الرسالة فارغًا'); return; }
                      if (item != null) {
                        await _save(item.keyName, b);
                      } else {
                        final title = nameCtrl.text.trim();
                        if (title.isEmpty) { _snack('أدخل اسم القالب'); return; }
                        final created = await _createCustom(title: title, body: b, tabIndex: tabIndex);
                        if (!created) return;
                        await _load();
                        if (mounted) _snack('تم إضافة القالب بنجاح');
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    }, child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)))),
                  ]),
                ]),
              ),
            );
          }),
        );
      },
    );
    nameCtrl.dispose();
    bodyCtrl.dispose();
  }

  Future<void> _repair() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('تأكيد إصلاح قوالب الرسائل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
      content: const Text('سيتم استعادة كافة قوالب الرسائل الافتراضية الخاصة بالنظام (العملاء، العروض، نقاط البيع، وسلفني) إلى حالتها الأصلية.\n\nالقوالب المخصصة التي أنشأتها بنفسك لن تتأثر.', style: TextStyle(fontFamily: 'Tajawal', height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بدء الإصلاح', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700))),
      ],
    )));
    if (ok != true) return;
    for (final tab in _tabsData) {
      for (final t in tab.items) {
        await _save(t.keyName, t.fallback);
      }
    }
    if (mounted) _snack('تمت استعادة القوالب الافتراضية');
  }

  void _menu(_Tpl t) {
    showModalBottomSheet<void>(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(Icons.edit_outlined, color: KayanPalette.of(ctx).primary), title: const Text('تعديل القالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); _edit(t); }),
      if (!t.isCustom)
        ListTile(leading: Icon(Icons.restart_alt_rounded, color: KayanPalette.of(ctx).primary), title: const Text('استعادة الافتراضي', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () async { Navigator.pop(ctx); await _save(t.keyName, t.fallback); }),
      if (t.isCustom)
        ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)), title: const Text('حذف القالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, color: Color(0xFFDC2626))), onTap: () async { Navigator.pop(ctx); await _deleteCustom(t); }),
    ]))));
  }

  Widget _card(_Tpl t) {
    final palette = KayanPalette.of(context);
    final body = _values[t.keyName] ?? t.fallback;
    // «افتراضي» يعني أن نص قالب النظام لم يُعدّل بعد — القوالب المخصّصة تُعرض مخصّصة دائماً.
    final isDefaultBody = !t.isCustom && body.trim() == t.fallback.trim();
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => _edit(t), child: Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border.withValues(alpha: 0.6))),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => _menu(t)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isDefaultBody ? palette.primary : palette.textTertiary)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isDefaultBody ? 'افتراضي' : 'مخصّص',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 11,
                color: isDefaultBody ? palette.primary : palette.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)), SizedBox(width: 4), Text('نشط', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w700))])),
          const Spacer(),
          Flexible(child: Text(t.title, textAlign: TextAlign.end, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: palette.primary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)), child: Text(_preview(body), style: TextStyle(fontFamily: 'Tajawal', height: 1.45, color: palette.textSecondary, fontSize: 13))),
      ]),
    ))));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('قوالب الرسائل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 17)),
          Text('تخصيص وإدارة رسائل العملاء ونقاط البيع والنظام وسلفني', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: [IconButton(tooltip: 'إصلاح القوالب', onPressed: _repair, icon: const Icon(Icons.build_circle_outlined))],
        bottom: TabBar(controller: _tabs, isScrollable: true, labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700), unselectedLabelStyle: const TextStyle(fontFamily: 'Tajawal'), tabs: [for (final t in _tabsData) Tab(text: t.label)]),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null), backgroundColor: const Color(0xFFC026A3), icon: const Icon(Icons.add, color: Colors.white), label: const Text('قالب جديد', style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.w700))),
      body: _loading
          ? const AsyncLoadingView(message: 'جاري تحميل القوالب…')
          : TabBarView(controller: _tabs, children: [
              for (final tab in _tabsData)
                Builder(builder: (_) {
                  final items = _tabItems(_tabsData.indexOf(tab));
                  return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: items.length, itemBuilder: (_, i) => _card(items[i]));
                }),
            ]),
    ));
  }
}
