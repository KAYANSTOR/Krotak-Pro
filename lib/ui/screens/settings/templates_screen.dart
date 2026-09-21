import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/services/default_pos_templates_seeder.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../widgets/async_views.dart';
import 'template_simulation_screen.dart';
import 'template_wizard_screen.dart';
import '../../../domain/services/local_transfer_template_activation_service.dart';

/// قائمة قوالب التحويل — مطابقة 100% لإطار فيديو Z Net (`tpl_sys50.jpg`).
///
/// - عنوان: قوالب {المحفظة} + عنوان فرعي
/// - بطاقة: ✓ أخضر · اسم القالب · شارة نشط · أولوية · Switch · ⋮
/// - قائمة ⋮: تعديل / حذف
/// - FAB بنفسجي: قالب جديد +
/// - ربط Domain: listByWallet / save / delete + reloadTemplates
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    this.walletId,
    this.walletName,
    this.posId,
    this.posName,
  });

  final String? walletId;
  final String? walletName;

  /// Scope the list to a single point-of-sale (parallel to [walletId]).
  final String? posId;
  final String? posName;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  bool _loading = true;
  bool _bulkBusy = false;
  String? _error;
  List<TransferTemplate> _items = const [];
  Map<String, String> _walletNames = const {};

  /// عدد القوالب النشطة من إجمالي قوالب هذا المصدر.
  int _activeCount = 0;

  /// مفتاح تجميع المصدر (نقطة بيع / محفظة) — null في العرض العام.
  String? get _groupKey {
    final pos = widget.posId?.trim();
    if (pos != null && pos.isNotEmpty) return 'pos:$pos';
    final wallet = widget.walletId?.trim();
    if (wallet != null && wallet.isNotEmpty) return 'wallet:$wallet';
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _reloadParser() async {
    await AppScope.of(context).reloadTemplates();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final wallets = await c.wallets.listAll();
    final names = <String, String>{};
    if (wallets is Success<List<Wallet>>) {
      for (final w in wallets.value) {
        names[w.id] = w.name;
      }
    }
    // إضافة الناقص فقط: أي إصدار قديم لا يملك إلا بعض قوالب الكتالوج
    // (طلب كرت / عدة كروت / رقم تسليم / طلب رصيد) يكتمل تلقائياً عند الفتح،
    // دون المساس بحالة القوالب الموجودة ولا بنصوص المشغّل.
    final posId = widget.posId?.trim();
    final posName = widget.posName?.trim();
    if (posId != null && posId.isNotEmpty && posName != null && posName.isNotEmpty) {
      final backfilled = await DefaultPosTemplatesSeeder(templates: c.transferTemplates)
          .seedForPos(posId: posId, posName: posName);
      if (backfilled is Success<int> && backfilled.value > 0) {
        await c.reloadTemplates();
      }
    }

    final r = widget.posId != null
        ? await c.transferTemplates.listAll()
        : widget.walletId == null
            ? await c.transferTemplates.listAll()
            : await c.transferTemplates.listByWallet(widget.walletId);
    final counts = _groupKey == null
        ? null
        : await LocalTransferTemplateActivationService(c.transferTemplates)
            .groupCounts(_groupKey!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _walletNames = names;
      if (r is Success<List<TransferTemplate>>) {
        // ترتيب حسب الأولوية تصاعدياً (الأقل = أعلى أولوية) كما في الفيديو
        final list = List<TransferTemplate>.from(
          widget.posId == null
              ? r.value
              : r.value.where((t) => t.posId == widget.posId),
        );
        list.sort((a, b) => a.priority.compareTo(b.priority));
        _items = list;
      } else {
        _error = (r as Failure).error.message;
      }
      if (counts is Success<({int active, int total})>) {
        _activeCount = counts.value.active;
      } else {
        _activeCount = _items.where((t) => t.isActive).length;
      }
    });
  }

  /// تفعيل/إيقاف كل قوالب المصدر بضغطة واحدة (بدل قالب واحد فقط).
  Future<void> _setAllActive(bool isActive) async {
    final key = _groupKey;
    if (key == null || _bulkBusy) return;
    final owner = widget.posName ?? widget.walletName ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isActive ? 'تفعيل كل القوالب؟' : 'إيقاف كل القوالب؟',
            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: Text(
            isActive
                ? 'سيتم تفعيل كل قوالب «$owner» معاً — وهكذا يستجيب النظام لجميع صيغ رسائل العملاء (طلب كرت، عدة كروت، رقم تسليم، طلب رصيد).'
                : 'سيتم إيقاف كل قوالب «$owner» — لن يعالج النظام أي رسالة واردة من هذا المصدر حتى تُفعّل قوالب مرة أخرى.',
            style: const TextStyle(fontFamily: 'Tajawal', height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                isActive ? 'تفعيل الكل' : 'إيقاف الكل',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _bulkBusy = true);
    final c = AppScope.of(context);
    final r = await LocalTransferTemplateActivationService(c.transferTemplates)
        .setGroupActive(key: key, isActive: isActive);
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    if (r is Failure<int>) {
      _snack(r.error.message);
      return;
    }
    final changed = (r as Success<int>).value;
    await _reloadParser();
    await _load();
    if (!mounted) return;
    if (changed == 0) {
      _snack(isActive ? 'كل القوالب مفعّلة بالفعل' : 'كل القوالب متوقفة بالفعل');
    } else {
      _snack(
        isActive
            ? 'تم تفعيل $changed قالباً — النظام يستجيب الآن لكل هذه الصيغ'
            : 'تم إيقاف $changed قالباً',
      );
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Tajawal'))),
    );
  }

  Future<void> _openWizard({TransferTemplate? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TemplateWizardScreen(
          existing: existing,
          initialWalletId: widget.walletId ?? existing?.walletId,
          initialPosId: widget.posId ?? existing?.posId,
        ),
      ),
    );
    if (saved == true) {
      await _reloadParser();
      await _load();
    }
  }

  Future<void> _toggle(TransferTemplate t, bool active) async {
    final c = AppScope.of(context);
    // حفظ القالب وحده: القوالب الأخرى لنفس المصدر تبقى نشطة (كانت تُلغى سابقاً
    // فتصبح نقطة البيع تستجيب لصيغة واحدة فقط).
    final r = await LocalTransferTemplateActivationService(c.transferTemplates)
        .save(t.copyWith(isActive: active));
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } else {
      await _reloadParser();
    }
    await _load();
  }

  Future<void> _delete(TransferTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'حذف القالب؟',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: Text(
            'سيتم حذف «${t.name}» نهائيًا.',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.netColors.rejected,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final c = AppScope.of(context);
    final r = await c.transferTemplates.delete(t.id);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } else {
      await _reloadParser();
    }
    await _load();
  }

  /// شريط حالة القوالب في المصدر: يوضّح أن القوالب المتعددة تعمل معاً،
  /// وينبّه إذا أصبح المصدر «أصمّ» (لا قالب نشط) ويقترح التفعيل الجماعي.
  Widget _activationBanner() {
    final palette = KayanPalette.of(context);
    final total = _items.length;
    final active = _activeCount;
    final deaf = active == 0;
    final partial = !deaf && active < total;
    if (!deaf && !partial) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.netColors.available.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.done_all_rounded, size: 18, color: context.netColors.available),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'كل القوالب نشطة ($active من $total) — يستجيب النظام لكل صيغ رسائل هذا المصدر',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final tone = deaf ? context.netColors.rejected : const Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(deaf ? Icons.notifications_off_rounded : Icons.info_outline_rounded, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  deaf
                      ? 'لا يوجد قالب نشط — النظام لن يستجيب لأي رسالة من هذا المصدر'
                      : '$active من $total قالب نشط — بعض صيغ الرسائل قد لا تُعالج (مثال: طلب عدة كروت أو رقم التسليم)',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 12.5, height: 1.45, color: palette.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _bulkBusy ? null : () => _setAllActive(true),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text(
                'تفعيل كل القوالب',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMenu(TransferTemplate t) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KayanPalette.of(ctx).border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: context.kayan.primary,
                  ),
                  title: const Text(
                    'تعديل',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openWizard(existing: t);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: context.netColors.rejected,
                  ),
                  title: Text(
                    'حذف',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                      color: context.netColors.rejected,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _delete(t);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = widget.posName ?? widget.walletName;
    final title = ownerName != null ? 'قوالب $ownerName' : 'قوالب التحويل';
    final subtitle = widget.posName != null
        ? 'إدارة قوالب نقطة البيع — $_activeCount من ${_items.length} نشط'
        : widget.walletName != null
            ? 'إدارة قوالب استخراج البيانات لهذه المحفظة — $_activeCount من ${_items.length} نشط'
            : 'إدارة قوالب استخراج البيانات';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(
              Icons.arrow_forward,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            if (_groupKey != null)
              PopupMenuButton<String>(
                tooltip: 'إدارة جماعية للقوالب',
                enabled: !_bulkBusy,
                onSelected: (value) => _setAllActive(value == 'on'),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'on',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.done_all_rounded, size: 20),
                      title: Text('تفعيل كل القوالب', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'off',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.block_rounded, size: 20),
                      title: Text('إيقاف كل القوالب', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ),
                ],
              ),
            IconButton(
              tooltip: 'محاكاة',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TemplateSimulationScreen(
                    initialWalletId: widget.walletId,
                  ),
                ),
              ),
              icon: Icon(Icons.science_outlined, color: context.kayan.primary),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openWizard(),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          icon: const Icon(Icons.add, size: 22),
          label: Text(
            widget.posId != null ? 'قالب POS جديد' : 'قالب جديد',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? AsyncEmptyView(
                        message: 'لا قوالب بعد',
                        actionLabel: 'إضافة قالب',
                        onAction: () => _openWizard(),
                      )
                    : Column(
                        children: [
                          if (_groupKey != null) _activationBanner(),
                          Expanded(
                            child: RefreshIndicator(
                              color: context.kayan.primary,
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) => _TemplateCard(
                                  template: _items[i],
                                  walletLabel: _items[i].walletId == null
                                      ? null
                                      : _walletNames[_items[i].walletId!],
                                  onToggle: (v) => _toggle(_items[i], v),
                                  onMenu: () => _showMenu(_items[i]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

/// بطاقة قالب مطابقة لإطار `tpl_sys50.jpg`:
/// [⋮] [Switch]  …  [اسم + شارات]  [✓]
/// مسودة = القالب ناقص حقلاً مطلوباً (المبلغ، أو معرّف العميل حسب نوعه) —
/// لا يمكن أن يكون نشطاً فعلياً حتى يُستكمل. مطابق لحالة "مسودة" في الفيديو.
bool _isTemplateDraft(TransferTemplate t) {
  final p = t.pattern.trim();
  if (p.isEmpty) return true;
  // طلب رصيد نقطة البيع: نص ثابت مثل «111»، الهوية من رقم المرسل.
  if (t.identifierKind == TemplateIdentifierKind.balanceRequestCode) return false;

  final hasAmount = p.contains('{amount}') || p.contains('%amount');
  final hasQty = p.contains('{qty}') || p.contains('%qty');
  final hasDest = p.contains('{dest}') ||
      p.contains('{phone}') ||
      p.contains('%phone') ||
      p.contains('{account}') ||
      p.contains('%account');

  // قوالب نقطة البيع: الهوية من رقم المرسل دائماً — يكفي المبلغ (ومع اختيار dest).
  final isPos = (t.posId ?? '').trim().isNotEmpty;
  if (isPos) {
    // طلب رصيد بلا مبلغ عولج أعلاه؛ أوامر الكروت تحتاج مبلغاً على الأقل.
    if (hasAmount || (hasQty && hasAmount)) return false;
    // نمط نصي ثابت مخصّص لنقطة البيع (نادر) — لا يُجبر كمسودة إن وُجد نص.
    if (p.isNotEmpty && !p.contains('{') && !p.contains('%')) return false;
    return !hasAmount;
  }

  if (!hasAmount) return true;
  final hasIdentifier = switch (t.identifierKind) {
    TemplateIdentifierKind.phone =>
      p.contains('{phone}') || p.contains('%phone') || hasDest,
    TemplateIdentifierKind.balanceRequestCode => true,
    _ => p.contains('{account}') || p.contains('%account') || hasDest,
  };
  return !hasIdentifier;
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onToggle,
    required this.onMenu,
    this.walletLabel,
  });

  final TransferTemplate template;
  final String? walletLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final draft = _isTemplateDraft(t);
    final active = t.isActive && !draft;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            // ⋮ قائمة
            IconButton(
              onPressed: onMenu,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
            // Switch — مسودة لا يمكن تفعيلها حتى تُستكمل
            Switch.adaptive(
              value: active,
              activeColor: context.kayan.primary,
              onChanged: draft ? null : onToggle,
            ),
            const SizedBox(width: 4),
            // المحتوى النصي
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    t.name,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // شارة نشط / متوقف / مسودة
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: draft
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                              : active
                                  ? context.netColors.available.withValues(alpha: 0.14)
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: draft
                                    ? const Color(0xFFF59E0B)
                                    : active
                                        ? context.netColors.available
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              draft ? 'مسودة' : (active ? 'نشط' : 'متوقف'),
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: draft
                                    ? const Color(0xFFF59E0B)
                                    : active
                                        ? context.netColors.available
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'أولوية: ${t.priority}',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (walletLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          walletLabel!,
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // أيقونة ✓ خضراء / ✏️ مسودة (مطابقة للفيديو)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: draft
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                    : active
                        ? context.netColors.availableContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                draft ? Icons.edit_note_rounded : Icons.check_circle,
                size: 22,
                color: draft
                    ? const Color(0xFFF59E0B)
                    : active
                        ? context.netColors.available
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
