import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../widgets/async_views.dart';
import 'template_simulation_screen.dart';
import 'template_wizard_screen.dart';

/// قائمة قوالب التحويل — مطابقة 100% لإطار فيديو Z Net (`tpl_sys50.jpg`).
///
/// - عنوان: قوالب {المحفظة} + عنوان فرعي
/// - بطاقة: ✓ أخضر · اسم القالب · شارة نشط · أولوية · Switch · ⋮
/// - قائمة ⋮: تعديل / حذف
/// - FAB بنفسجي: قالب جديد +
/// - ربط Domain: listByWallet / save / delete + reloadTemplates
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, this.walletId, this.walletName});

  final String? walletId;
  final String? walletName;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  bool _loading = true;
  String? _error;
  List<TransferTemplate> _items = const [];
  Map<String, String> _walletNames = const {};

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
    final r = widget.walletId == null
        ? await c.transferTemplates.listAll()
        : await c.transferTemplates.listByWallet(widget.walletId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _walletNames = names;
      if (r is Success<List<TransferTemplate>>) {
        // ترتيب حسب الأولوية تصاعدياً (الأقل = أعلى أولوية) كما في الفيديو
        final list = List<TransferTemplate>.from(r.value);
        list.sort((a, b) => a.priority.compareTo(b.priority));
        _items = list;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  Future<void> _openWizard({TransferTemplate? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TemplateWizardScreen(
          existing: existing,
          initialWalletId: widget.walletId ?? existing?.walletId,
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
    final r = await c.transferTemplates.save(t.copyWith(isActive: active));
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
                    color: Colors.grey.shade300,
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
                  title: const Text(
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
    final title = widget.walletName != null
        ? 'قوالب ${widget.walletName}'
        : 'قوالب التحويل';
    final subtitle = widget.walletName != null
        ? 'إدارة قوالب استخراج البيانات لهذه المحفظة'
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
          label: const Text(
            'قالب جديد',
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
                    : RefreshIndicator(
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
    );
  }
}

/// بطاقة قالب مطابقة لإطار `tpl_sys50.jpg`:
/// [⋮] [Switch]  …  [اسم + شارات]  [✓]
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
    final active = t.isActive;

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
            // Switch
            Switch.adaptive(
              value: active,
              activeColor: context.kayan.primary,
              onChanged: onToggle,
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
                      // شارة نشط / متوقف
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: active
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
                                color: active
                                    ? context.netColors.available
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              active ? 'نشط' : 'متوقف',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: active
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
            // أيقونة ✓ خضراء (مطابقة للفيديو)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? context.netColors.availableContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.check_circle,
                size: 22,
                color: active
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
