import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/async_views.dart';
import 'template_simulation_screen.dart';
import 'template_wizard_screen.dart';

/// قائمة قوالب التحويل — مطابقة أسلوب فيديو Z Net (أولوية + تفعيل + قائمة).
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
        _items = r.value;
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
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
    } else {
      await _reloadParser();
    }
    await _load();
  }

  Future<void> _delete(TransferTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب؟', style: TextStyle(fontFamily: 'Tajawal')),
        content: Text('سيتم حذف «${t.name}» نهائيًا.', style: const TextStyle(fontFamily: 'Tajawal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal'))),
        ],
      ),
    );
    if (ok != true) return;
    final c = AppScope.of(context);
    final r = await c.transferTemplates.delete(t.id);
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
    } else {
      await _reloadParser();
    }
    await _load();
  }

  void _menu(TransferTemplate t) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل', style: TextStyle(fontFamily: 'Tajawal')),
              onTap: () {
                Navigator.pop(ctx);
                _openWizard(existing: t);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('حذف', style: TextStyle(fontFamily: 'Tajawal', color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(t);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kayan = context.kayan;
    final title = widget.walletName != null ? 'قوالب ${widget.walletName}' : 'قوالب التحويل';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kayan.appBackground,
        appBar: AppBar(
          backgroundColor: kayan.surface,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800, color: kayan.textPrimary)),
              Text(
                'إدارة قوالب استخراج البيانات',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textSecondary),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'محاكاة',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TemplateSimulationScreen(initialWalletId: widget.walletId)),
              ),
              icon: const Icon(Icons.science_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openWizard(),
          backgroundColor: const Color(0xFFA855F7),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('قالب جديد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : _items.isEmpty
                    ? AsyncEmptyView(message: 'لا قوالب', actionLabel: 'إضافة', onAction: () => _openWizard())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final t = _items[i];
                            final walletLabel = t.walletId == null ? null : _walletNames[t.walletId!];
                            return Material(
                              color: kayan.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _menu(t),
                                      icon: Icon(Icons.more_vert, color: kayan.textTertiary),
                                    ),
                                    Switch.adaptive(
                                      value: t.isActive,
                                      onChanged: (v) => _toggle(t, v),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            t.name,
                                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, color: kayan.textPrimary),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: t.isActive
                                                      ? const Color(0xFF059669).withValues(alpha: 0.12)
                                                      : kayan.surfaceVariant,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  t.isActive ? 'نشط' : 'متوقف',
                                                  style: TextStyle(
                                                    fontFamily: 'Tajawal',
                                                    fontSize: 11,
                                                    color: t.isActive ? const Color(0xFF059669) : kayan.textTertiary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'أولوية: ${t.priority}',
                                                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: kayan.textSecondary),
                                              ),
                                              if (walletLabel != null) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  walletLabel,
                                                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: kayan.textTertiary),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.check_circle,
                                      color: t.isActive ? const Color(0xFF10B981) : kayan.border,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
