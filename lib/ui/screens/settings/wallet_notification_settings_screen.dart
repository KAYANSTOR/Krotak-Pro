import 'package:flutter/material.dart';
import '../../../core/result.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/entities/payment_event.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

class WalletNotificationSettingsScreen extends StatefulWidget {
  const WalletNotificationSettingsScreen({super.key});
  @override
  State<WalletNotificationSettingsScreen> createState() => _WalletNotificationSettingsScreenState();
}

class _WalletNotificationSettingsScreenState extends State<WalletNotificationSettingsScreen> {
  bool _accessGranted = false;
  bool _loading = true;
  List<PaymentSource> _sources = const [];

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final access = await c.notificationBridge.isAccessGranted();
    final result = await c.notificationSources.list();
    if (!mounted) return;
    setState(() { _accessGranted = access; _loading = false; _sources = result is Success<List<PaymentSource>> ? result.value : const []; });
  }

  Future<void> _openAccess() => AppScope.of(context).notificationBridge.openAccessSettings();
  Future<void> _sync() async { await AppScope.of(context).notificationHandler.refreshSources(); await _load(); }

  Future<void> _add() async {
    final name = TextEditingController();
    final package = TextEditingController();
    final saved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إضافة مصدر محفظة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المحفظة')),
        const SizedBox(height: 12),
        TextField(controller: package, decoration: const InputDecoration(labelText: 'اسم حزمة Android', hintText: 'com.example.wallet')),
        const SizedBox(height: 8),
        const Text('لا نخمن أسماء الحزم. استخدم الاسم الفعلي للتطبيق بعد التحقق منه على الجهاز.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    if (saved != true || !mounted) { name.dispose(); package.dispose(); return; }
    final result = await AppScope.of(context).notificationSources.upsert(displayName: name.text, packageName: package.text, enabled: true);
    name.dispose(); package.dispose();
    if (result is Failure) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message))); return; }
    await _sync();
  }

  Future<void> _toggle(PaymentSource source, bool enabled) async {
    final result = await AppScope.of(context).notificationSources.setEnabled(source.packageName!, enabled);
    if (result is Failure) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message))); return; }
    await _sync();
  }

  Future<void> _remove(PaymentSource source) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('حذف المصدر'),
      content: Text('سيتم إيقاف استقبال إشعارات ${source.displayName}.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))],
    ));
    if (yes != true || !mounted) return;
    await AppScope.of(context).notificationSources.remove(source.packageName!);
    await _sync();
  }


  /// يسجّل كل محفظة بوضع إشعار كمصدر مفعّل في السجل — الربط الفعلي مع المحرك.
  Future<void> _syncFromWallets() async {
    final c = AppScope.of(context);
    final wallets = await c.walletCatalog.listEnriched();
    if (wallets is Failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((wallets as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
        );
      }
      return;
    }
    var n = 0;
    for (final w in (wallets as Success).value) {
      final pkg = (w.packageName ?? '').trim();
      if (w.sourceMode != WalletSourceMode.notification || pkg.isEmpty) continue;
      final r = await c.notificationSources.upsert(
        displayName: w.name,
        packageName: pkg,
        enabled: w.status == WalletStatus.active,
      );
      if (r is Success) n++;
    }
    await _sync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت مزامنة $n مصدر إشعار من المحافظ', style: const TextStyle(fontFamily: 'Tajawal'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إشعارات المحافظ'),
          actions: [
            TextButton(
              onPressed: _loading ? null : _syncFromWallets,
              child: const Text('مزامنة المحافظ', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: _loading
            ? const AsyncLoadingView(skeleton: true, skeletonCount: 3)
            : RefreshIndicator(
                onRefresh: _load,
                color: palette.primary,
                child: ListView(
                  padding: NetSpacing.screen,
                  children: [
                    NetSurfaceCard(
                      borderColor: (_accessGranted ? net.available : net.rejected)
                          .withValues(alpha: 0.5),
                      child: Row(
                        children: [
                          Icon(
                            _accessGranted
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_off_rounded,
                            color: _accessGranted ? net.available : net.rejected,
                            size: 24,
                          ),
                          const SizedBox(width: NetSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _accessGranted
                                      ? 'وصول الإشعارات مفعّل'
                                      : 'وصول الإشعارات غير مفعّل',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: NetSpacing.xs),
                                Text(
                                  'يتم قراءة إشعارات مصادر الدفع التي يحددها المشغّل فقط.',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12,
                                    height: 1.35,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_accessGranted) ...[
                      const SizedBox(height: NetSpacing.md),
                      FilledButton.icon(
                        onPressed: _openAccess,
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: const Text('فتح إعدادات الوصول'),
                      ),
                    ],
                    const SizedBox(height: NetSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'مصادر الدفع عبر الإشعارات',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'إضافة مصدر',
                          onPressed: _add,
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: palette.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NetSpacing.sm),
                    if (_sources.isEmpty)
                      AsyncEmptyView(
                        message: 'لم تتم إضافة أي مصدر',
                        hint:
                            'لا يتم تخمين اسم الحزمة أو معالجة تطبيقات غير مهيأة — أضف المصدر بعد التحقق منه على الجهاز.',
                        icon: Icons.account_balance_wallet_outlined,
                        actionLabel: 'إضافة مصدر',
                        onAction: _add,
                        compact: true,
                      )
                    else
                      for (final source in _sources) ...[
                        NetSurfaceCard(
                          margin: const EdgeInsets.only(bottom: NetSpacing.sm),
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: NetSpacing.row,
                            leading: Icon(
                              Icons.account_balance_wallet_outlined,
                              color: palette.primary,
                            ),
                            title: Text(
                              source.displayName,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              source.packageName ?? '—',
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12,
                                color: palette.textTertiary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch.adaptive(
                                  value: source.enabled,
                                  activeTrackColor: palette.primary,
                                  onChanged: (v) => _toggle(source, v),
                                ),
                                IconButton(
                                  tooltip: 'حذف المصدر',
                                  onPressed: () => _remove(source),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: net.rejected,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    const SizedBox(height: NetSpacing.lg),
                    NetInlineNotice(
                      message:
                          'يُحفظ الإشعار مؤقتًا في طابور نقل مشفّر، ثم يُمرر إلى محرك الدفع الموحد. الفشل في المعالجة لا يحذف الحركة من سجل المراجعة.',
                      icon: Icons.shield_outlined,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
