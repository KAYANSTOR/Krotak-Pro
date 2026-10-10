import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/default_outbound_templates_seeder.dart';
import '../../../domain/services/outbound_template_activation.dart';
import '../../../domain/services/outbound_template_catalog.dart';
import '../../../domain/services/outbound_template_renderer.dart';
import '../../app_scope.dart';
import '../../perf/screen_open_trace.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/async_views.dart';
import '../../errors/user_facing_error_localizer.dart';

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
    this.target,
  });
  final String keyName;
  final String title;
  final String fallback;
  final List<String> vars;

  /// قالب أنشأه المشغّل بنفسه (لا قالب نظام) — قابل للحذف.
  final bool isCustom;

  /// مفتاح قالب النظام الذي يستبدله هذا القالب المخصّص عند تفعيله.
  final String? target;

  /// معرّف القالب المخصّص (بدون البادئة `custom:`).
  String get customId => keyName.startsWith('custom:') ? keyName.substring(7) : keyName;
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

  /// بحث موحّد في **كل** التبويبات (اسم القالب أو نصه) — القوالب صارت 18.
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// القوالب المخصّصة التي أنشأها المشغّل — مفهرسة برقم التبويب.
  final Map<int, List<_Tpl>> _custom = <int, List<_Tpl>>{};

  /// الاستبدالات الفعّالة: مفتاح قالب النظام ← معرّف القالب المخصّص.
  Map<String, String> _active = <String, String>{};

  OutboundTemplateActivation get _activation {
    final c = AppScope.of(context);
    return OutboundTemplateActivation(settings: c.settings, clock: c.clock);
  }

  _Tpl? _systemTpl(String key) {
    for (final tab in _tabsData) {
      for (final t in tab.items) {
        if (t.keyName == key) return t;
      }
    }
    return null;
  }

  bool _isActive(_Tpl t) {
    if (t.isCustom) return t.target != null && _active[t.target] == t.customId;
    return !_active.containsKey(t.keyName);
  }

  /// التبويبات مشتقّة من العقد المركزي [OutboundTemplateCatalog].
  ///
  /// لا تُعرّف أي قائمة قوالب يدويًا هنا: العنوان والمتغيرات والنص الأولي كلها
  /// من [OutboundTemplateDefinition]، فتبقى واجهة الإعدادات والزرع والتحقق
  /// والاختبارات على عقد واحد.
  static final _tabsData = _buildTabs();

  static List<_TabDef> _buildTabs() => <_TabDef>[
        for (final category in OutboundTemplateCategory.tabOrder)
          _TabDef(category.tabLabel, <_Tpl>[
            for (final definition in OutboundTemplateCatalog.definitions)
              if (definition.category == category)
                _Tpl(
                  definition.key,
                  definition.title,
                  definition.initialBody,
                  definition.variables.toList(growable: false),
                ),
          ]),
      ];

  @override
  void initState() {
    super.initState();
    final i = widget.initialTab.clamp(0, _tabsData.length - 1);
    _tabs = TabController(length: _tabsData.length, vsync: this, initialIndex: i);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// المتغيرات المكتوبة `{name}` في نص القالب ولم تُعرّف له — تكشف خطأ إملائياً
  /// يصل للعميل حرفياً (مثل `{serial_number}`) بدل قيمته.
  List<String> _unknownVars(_Tpl t, String body) {
    final known = t.vars.toSet();
    final found = <String>{};
    for (final match in RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}').allMatches(body)) {
      final name = match.group(1)!;
      if (!known.contains(name)) found.add(name);
    }
    final list = found.toList()..sort();
    return list;
  }

  /// نتائج البحث عبر التبويبات: (القالب، رقم التبويب، عدد المتغيرات المجهولة).
  List<({_Tpl tpl, int tab, List<String> unknown})> get _hits {
    final q = _query.toLowerCase();
    final out = <({_Tpl tpl, int tab, List<String> unknown})>[];
    for (var i = 0; i < _tabsData.length; i++) {
      for (final t in _tabItems(i)) {
        final body = _values[t.keyName] ?? t.fallback;
        if (t.title.toLowerCase().contains(q) || body.toLowerCase().contains(q)) {
          out.add((tpl: t, tab: i, unknown: _unknownVars(t, body)));
        }
      }
    }
    return out;
  }

  int _tabCount(int index) => _tabItems(index).length;

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
            final targetRaw = (entry['target'] as String?)?.trim();
            final target = (targetRaw != null && _systemTpl(targetRaw) != null) ? targetRaw : null;
            // النص يُقرأ من مصدره الوحيد `custom:<id>`، وليس من السجل.
            final bodyResult = await c.settings.find(key);
            final body = bodyResult is Success<AppSetting?>
                ? (bodyResult.value?.value ?? '')
                : '';
            next[key] = body;
            (custom[index] ??= <_Tpl>[]).add(
              _Tpl(key, title, body, const ['CARD_CODE', 'CARD_VALUE', 'CURRENCY', 'NETWORK_NAME', 'amount', 'balance', 'pos', 'reason'], isCustom: true, target: target),
            );
          }
        }
      } on FormatException {
        // إعداد قديم/تالف — يتم تجاهله ولا يعطّل الشاشة.
      }
    }

    // الاستبدالات الفعّالة: نتجاهل أي سجل قديم لا يطابق قالباً مخصّصاً موجوداً،
    // ونعرض نص النظام الأصلي (لا المُرسَل) على بطاقة قالب النظام المستبدَل.
    final activation = _activation;
    final storedActive = await activation.loadActive();
    final active = <String, String>{};
    for (final entry in storedActive.entries) {
      final match = custom.values
          .expand((list) => list)
          .where((t) => t.customId == entry.value && t.target == entry.key)
          .firstOrNull;
      final sys = _systemTpl(entry.key);
      if (match == null || sys == null) continue;
      // قالب النظام لم يُلمس: بطاقة قالب النظام تعرض نص النظام الحقيقي،
      // وبطاقة القالب المخصّص تعرض نص القالب المخصّص الفعّال.
      active[entry.key] = entry.value;
    }

    ScreenOpenTrace.instance.markLatestDataReady(ScreenOpenIds.outboundTemplates);
    if (!mounted) return;
    setState(() {
      _values..clear()..addAll(next);
      _custom..clear()..addAll(custom);
      _active = active;
      _loading = false;
    });
  }

  static String _customKey(String id) => SettingKeys.customOutboundBody(id);

  List<_Tpl> _tabItems(int index) => <_Tpl>[
        ..._tabsData[index].items,
        ...?_custom[index],
      ];

  /// حفظ قالب جديد فعلياً: يُضاف للسجل ويُحفظ نصه، فلا يضيع كما كان سابقاً.
  Future<String?> _createCustom({
    required String title,
    required String body,
    required int tabIndex,
    required String target,
  }) async {
    final c = AppScope.of(context);
    final id = c.ids.next('tpl').replaceAll(':', '-');
    // السجل يحمل **metadata فقط** (المعرّف/الاسم/التبويب/الهدف).
    // نص القالب له مصدر واحد وحيد: مفتاح `custom:<id>` في الإعدادات.
    // لا يُخزَّن النص في السجل أبدًا حتى لا يوجد مصدران متنافسان.
    final entry = <String, Object?>{
      'id': id,
      'title': title,
      'tab': tabIndex,
      'target': target,
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
      if (mounted) _snack(localizedError(bodySaved.error));
      return null;
    }
    final saved = await c.settings.save(
      AppSetting(
        key: SettingKeys.customOutboundTemplates,
        value: jsonEncode(list),
        updatedAt: c.clock.now(),
      ),
    );
    if (saved is Failure) {
      if (mounted) _snack(localizedError(saved.error));
      return null;
    }
    return id;
  }

  Future<List<Map<String, Object?>>> _readRegistry() async {
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
        // سجل تالف — يُعامل كفارغ.
      }
    }
    return list;
  }

  Future<Result<void>> _writeRegistry(List<Map<String, Object?>> list) async {
    final c = AppScope.of(context);
    return c.settings.save(
      AppSetting(
        key: SettingKeys.customOutboundTemplates,
        value: jsonEncode(list),
        updatedAt: c.clock.now(),
      ),
    );
  }

  /// يُزيل نص القالب المخصّص من مصدره الوحيد.
  ///
  /// إن كان المخزن يدعم الحذف الفعلي([SettingsPurge]) يُحذف المفتاح، وإلا
  /// تُكتب قيمة فارغة — والاثنتان تمنعان الإرسال تمامًا فلا يبقى أثر فعّال.
  Future<Result<void>> _purgeCustomBody(String key) async {
    final c = AppScope.of(context);
    final repo = c.settings;
    if (repo is SettingsPurge) return repo.delete(key);
    return repo.save(
      AppSetting(key: key, value: '', updatedAt: c.clock.now()),
    );
  }

  /// تفعيل قالب مخصّص: يصبح هو النص المُرسَل فعلياً بدل قالب النظام الذي يستبدله.
  Future<void> _activateCustom(_Tpl t) async {
    var target = t.target;
    target ??= await _pickTarget(t);
    if (target == null || !mounted) return;
    final sys = _systemTpl(target);
    if (sys == null) return;
    if (t.target != target) {
      final targetSaved = await _setTarget(t, target);
      if (targetSaved is Failure<void>) {
        if (mounted) _snack(localizedError(targetSaved.error));
        return;
      }
    }
    final r = await _activation.activate(
      systemKey: target,
      customId: t.customId,
    );
    if (!mounted) return;
    if (r is Failure<void>) {
      _snack(localizedError(r.error));
      return;
    }
    await _load();
    _snack('تم تفعيل «${t.title}» — سيُرسل بدل «${sys.title}»');
  }

  /// إلغاء الاستبدال: يعود قالب النظام الأصلي هو المُرسَل.
  Future<void> _activateSystem(_Tpl t) async {
    final r = await _activation.revert(systemKey: t.keyName);
    if (!mounted) return;
    if (r is Failure<void>) {
      _snack(localizedError(r.error));
      return;
    }
    await _load();
    _snack('تم تفعيل القالب الافتراضي «${t.title}»');
  }

  Future<Result<void>> _setTarget(_Tpl t, String target) async {
    final list = await _readRegistry();
    for (final e in list) {
      if (_customKey((e['id'] as String?) ?? '') == t.keyName) e['target'] = target;
    }
    return _writeRegistry(list);
  }

  /// يختار القالب (من نفس التبويب) الذي سيستبدله القالب المخصّص.
  Future<String?> _pickTarget(_Tpl t) async {
    final tab = _custom.entries.firstWhere((e) => e.value.contains(t), orElse: () => MapEntry(0, <_Tpl>[])).key;
    final options = _tabsData[tab].items;
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('أي قالب سيستبدله؟', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
          children: [
            for (final o in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, o.keyName),
                child: Text(o.title, style: const TextStyle(fontFamily: 'Tajawal')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeTarget(_Tpl t) async {
    final target = await _pickTarget(t);
    if (target == null || target == t.target || !mounted) return;
    final wasActive = _isActive(t);
    if (wasActive && t.target != null) {
      final old = _systemTpl(t.target!);
      if (old != null) {
        final reverted = await _activation.revert(systemKey: old.keyName);
        if (reverted is Failure<void>) {
          if (mounted) _snack(localizedError(reverted.error));
          return;
        }
      }
    }
    final targetSaved = await _setTarget(t, target);
    if (targetSaved is Failure<void>) {
      if (mounted) _snack(localizedError(targetSaved.error));
      return;
    }
    await _load();
    if (wasActive && mounted) {
      final fresh = _tabItems(_custom.entries.firstWhere((e) => e.value.any((x) => x.keyName == t.keyName)).key)
          .firstWhere((x) => x.keyName == t.keyName);
      await _activateCustom(fresh);
    }
  }

  Future<void> _deleteCustom(_Tpl t) async {
    final c = AppScope.of(context);
    if (_isActive(t) && t.target != null) {
      final sys = _systemTpl(t.target!);
      if (sys != null) {
        // إلغاء التفعيل قبل حذف النص: لا يبقى مؤشر يشير إلى قالب محذوف.
        final reverted = await _activation.revert(systemKey: sys.keyName);
        if (reverted is Failure<void>) {
          if (mounted) _snack(localizedError(reverted.error));
          return;
        }
      }
    }
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
    final registrySaved = await c.settings.save(
      AppSetting(
        key: SettingKeys.customOutboundTemplates,
        value: jsonEncode(list),
        updatedAt: c.clock.now(),
      ),
    );
    if (registrySaved is Failure<void>) {
      if (mounted) _snack(localizedError(registrySaved.error));
      return;
    }
    // حذف نص القالب نفسه: لا يبقى مفتاح يتيم قابل للقراءة بعد اختفاء تعريفه.
    final purge = await _purgeCustomBody(t.keyName);
    if (purge is Failure<void>) {
      if (mounted) _snack(localizedError(purge.error));
      return;
    }
    if (mounted) _snack('تم حذف القالب');
    await _load();
  }

  Future<void> _save(String key, String value) async {
    final c = AppScope.of(context);
    // نص قالب النظام أو المخصص يُحفظ في مفتاحه الوحيد، دون نسخة في السجل.
    final r = await c.settings.save(
      AppSetting(key: key, value: value, updatedAt: c.clock.now()),
    );
    if (!mounted) return;
    if (r is Failure<void>) { _snack(localizedError(r.error)); return; }
    setState(() => _values[key] = value);
    _snack('تم تحديث القالب بنجاح');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Tajawal'))));
  }

  /// تستخدم المعاينة المتغيرات المسموحة للقالب الذي سيُستبدل فعلياً.
  String _preview(String body, {String? templateKey}) {
    if (body.trim().isEmpty) return '—';
    final definition = templateKey == null
        ? null
        : OutboundTemplateCatalog.byKey(templateKey);
    final rendered = OutboundTemplateRenderer.renderStrict(
      template: body,
      values: definition == null
          ? OutboundTemplateCatalog.previewSamples
          : OutboundTemplateCatalog.previewValuesFor(definition),
    );
    if (rendered is Success<String>) return rendered.value;
    return '⛔ لن تُرسل هذه الرسالة: ${localizedError((rendered as Failure<String>).error)}';
  }

  String _variableLabel(String variable) => const <String, String>{
        'NETWORK_NAME': 'اسم الشبكة',
        'CARD_CODE': 'كود الكرت',
        'CARD_VALUE': 'فئة الكرت',
        'CURRENCY': 'العملة',
        'serial': 'رقم الكرت',
        'code': 'الرمز',
        'secret': 'الرمز السري',
        'SECRET': 'الرمز السري',
        'CODE': 'الرمز',
        'cards': 'بيانات الكروت',
        'QUANTITY_TEXT': 'عدد الكروت',
        'CUSTOMER_PHONE': 'رقم العميل',
        'POS_NAME': 'اسم نقطة البيع',
        'TOTAL': 'الإجمالي',
        'AMOUNT': 'المبلغ',
        'category': 'الفئة',
        'amount': 'المبلغ',
        'balance': 'الرصيد',
        'debt': 'الدين',
        'reason': 'السبب',
        'count': 'العدد',
      }[variable] ?? variable;

  Future<void> _edit(_Tpl? item) async {
    final isNew = item == null;
    var tabIndex = _tabs.index.clamp(0, _tabsData.length - 1);
    String? targetKey;
    var activateNow = true;
    String effectiveTarget() {
      final items = _tabsData[tabIndex].items;
      return items.any((x) => x.keyName == targetKey) ? targetKey! : items.first.keyName;
    }
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
                          setLocal(() {
                            tabIndex = value;
                            targetKey = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('target-$tabIndex'),
                        value: effectiveTarget(),
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'يستبدل القالب', labelStyle: const TextStyle(fontFamily: 'Tajawal'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        items: [
                          for (final o in _tabsData[tabIndex].items)
                            DropdownMenuItem(value: o.keyName, child: Text(o.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Tajawal'))),
                        ],
                        onChanged: (value) => setLocal(() => targetKey = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: activateNow,
                        onChanged: (v) => setLocal(() => activateNow = v),
                        title: const Text('تفعيله فوراً (يُرسل بدل القالب المحدد)', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                      ),
                      const SizedBox(height: 4),
                    ],
                    TextField(controller: nameCtrl, style: const TextStyle(fontFamily: 'Tajawal'), decoration: InputDecoration(labelText: 'اسم القالب', labelStyle: const TextStyle(fontFamily: 'Tajawal'), prefixIcon: const Icon(Icons.title_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    TextField(controller: bodyCtrl, minLines: 4, maxLines: 8, onChanged: (_) => setLocal(() {}), style: const TextStyle(fontFamily: 'Tajawal', height: 1.4), decoration: InputDecoration(labelText: 'نص رسالة الـ SMS', labelStyle: const TextStyle(fontFamily: 'Tajawal'), prefixIcon: const Icon(Icons.sms_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), alignLabelWithHint: true)),
                    const SizedBox(height: 12),
                    if (item != null && _unknownVars(item, bodyCtrl.text).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'تنبيه: المتغيرات التالية غير معروفة وستُرسل كما هي: '+_unknownVars(item, bodyCtrl.text).map((v) => '{$v}').join('، '),
                          style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: Color(0xFFDC2626), height: 1.4),
                        ),
                      ),
                    const Text('أزرار المساعدة للمتغيرات (اضغط لإدراجها في مكان مؤشر الكتابة):', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final v in vars)
                        ActionChip(label: Text(_variableLabel(v), style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)), onPressed: () {
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
                      Text(
                        body.isEmpty
                            ? '—'
                            : _preview(
                                body,
                                templateKey: item?.isCustom == true
                                    ? item?.target
                                    : (item?.keyName ?? effectiveTarget()),
                              ),
                        style: const TextStyle(fontFamily: 'Tajawal', height: 1.45),
                      ),
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
                        final created = await _createCustom(title: title, body: b, tabIndex: tabIndex, target: effectiveTarget());
                        if (created == null) return;
                        await _load();
                        final tpl = _custom.values.expand((l) => l).where((t) => t.customId == created).firstOrNull;
                        if (activateNow && tpl != null) {
                          await _activateCustom(tpl);
                        } else if (mounted) {
                          _snack('تم إضافة القالب (غير مفعّل)');
                        }
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
    // الاستعادة تعني عودة نصوص النظام للإرسال: تُلغى الاستبدالات الفعّالة أولاً
    // (القوالب المخصّصة تبقى لكن غير فعّالة).
    await _activation.clear();
    _active = <String, String>{};
    for (final tab in _tabsData) {
      for (final t in tab.items) {
        await _save(t.keyName, t.fallback);
      }
    }
    await _load();
    if (mounted) _snack('تمت استعادة القوالب الافتراضية');
  }

  void _menu(_Tpl t) {
    showModalBottomSheet<void>(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (ctx) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(Icons.edit_outlined, color: KayanPalette.of(ctx).primary), title: const Text('تعديل القالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); _edit(t); }),
      if (!_isActive(t))
        ListTile(leading: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981)), title: Text(t.isCustom ? 'تفعيل هذا القالب' : 'تفعيل القالب الافتراضي', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); t.isCustom ? _activateCustom(t) : _activateSystem(t); }),
      if (t.isCustom)
        ListTile(leading: Icon(Icons.swap_horiz_rounded, color: KayanPalette.of(ctx).primary), title: const Text('تغيير القالب الذي يستبدله', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); _changeTarget(t); }),
      if (!t.isCustom)
        ListTile(leading: Icon(Icons.restart_alt_rounded, color: KayanPalette.of(ctx).primary), title: const Text('استعادة الافتراضي', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)), onTap: () async { Navigator.pop(ctx); await _save(t.keyName, t.fallback); }),
      if (t.isCustom)
        ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)), title: const Text('حذف القالب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, color: Color(0xFFDC2626))), onTap: () async { Navigator.pop(ctx); await _deleteCustom(t); }),
    ]))));
  }

  /// نتائج البحث عبر كل التبويبات، مع اسم التبويب فوق كل نتيجة.
  Widget _searchResults() {
    final hits = _hits;
    if (hits.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: [
          AsyncEmptyView(
            message: 'لا نتائج للبحث «$_query»',
            icon: Icons.search_off_rounded,
            actionLabel: 'مسح البحث',
            onAction: () => _searchCtrl.clear(),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: hits.length,
      itemBuilder: (_, i) {
        final hit = hits[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                _tabsData[hit.tab].label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _card(hit.tpl),
          ],
        );
      },
    );
  }

  Widget _card(_Tpl t) {
    final palette = KayanPalette.of(context);
    final body = _values[t.keyName] ?? t.fallback;
    final unknown = _unknownVars(t, body);
    // «افتراضي» يعني أن نص قالب النظام لم يُعدّل بعد — القوالب المخصّصة تُعرض مخصّصة دائماً.
    final isDefaultBody = !t.isCustom && body.trim() == t.fallback.trim();
    final isActive = _isActive(t);
    final targetTitle = t.target == null ? null : _systemTpl(t.target!)?.title;
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
          if (isActive)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)), SizedBox(width: 4), Text('نشط', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w700))]))
          else
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => t.isCustom ? _activateCustom(t) : _activateSystem(t),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: palette.textTertiary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.radio_button_unchecked, size: 14, color: palette.textTertiary), const SizedBox(width: 4), Text('غير نشط · اضغط للتفعيل', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: palette.textTertiary, fontWeight: FontWeight.w700))])),
            ),
          if (unknown.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 13, color: Color(0xFFDC2626)),
                  const SizedBox(width: 4),
                  Text(
                    'متغير غير معروف',
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          Flexible(child: Text(t.title, textAlign: TextAlign.end, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        if (t.isCustom)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              targetTitle == null ? 'غير مرتبط بقالب — من القائمة اختر «تغيير القالب الذي يستبدله»' : 'يستبدل: $targetTitle',
              style: TextStyle(fontFamily: 'Tajawal', fontSize: 11.5, color: targetTitle == null ? const Color(0xFFDC2626) : palette.textSecondary),
            ),
          ),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: palette.primary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)), child: Text(_preview(body, templateKey: t.isCustom ? t.target : t.keyName), style: TextStyle(fontFamily: 'Tajawal', height: 1.45, color: palette.textSecondary, fontSize: 13))),
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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Tajawal'),
          tabs: [
            for (var i = 0; i < _tabsData.length; i++)
              Tab(text: '${_tabsData[i].label} (${_tabCount(i)})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null), backgroundColor: const Color(0xFFC026A3), icon: const Icon(Icons.add, color: Colors.white), label: const Text('قالب جديد', style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.w700))),
      body: _loading
          ? const AsyncLoadingView(message: 'جاري تحميل القوالب…')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontFamily: 'Tajawal'),
                    decoration: InputDecoration(
                      hintText: 'ابحث في كل القوالب (الاسم أو النص)…',
                      hintStyle: const TextStyle(fontFamily: 'Tajawal'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              icon: const Icon(Icons.close),
                              onPressed: () => _searchCtrl.clear(),
                            ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _query.isEmpty
                      ? TabBarView(controller: _tabs, children: [
                          for (final tab in _tabsData)
                            Builder(builder: (_) {
                              final items = _tabItems(_tabsData.indexOf(tab));
                              return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: items.length, itemBuilder: (_, i) => _card(items[i]));
                            }),
                        ])
                      : _searchResults(),
                ),
              ],
            ),
    ));
  }
}
