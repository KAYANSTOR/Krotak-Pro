import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/payment_event.dart';
import '../../../domain/entities/wallet.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

/// مصادر إشعارات المحافظ — شاشة فرعية كاملة (إذن الوصول + قائمة المصادر + مزامنة).
class WalletNotificationSettingsScreen extends StatefulWidget {
  const WalletNotificationSettingsScreen({super.key});

  @override
  State<WalletNotificationSettingsScreen> createState() =>
      _WalletNotificationSettingsScreenState();
}

class _WalletNotificationSettingsScreenState
    extends State<WalletNotificationSettingsScreen> {
  bool _accessGranted = false;
  bool _loading = true;
  String? _error;
  List<PaymentSource> _sources = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = AppScope.of(context);
      final access = await c.notificationBridge.isAccessGranted();
      final result = await c.notificationSources.list();
      if (!mounted) return;
      setState(() {
        _accessGranted = access;
        _loading = false;
        if (result is Failure<List<PaymentSource>>) {
          _error = result.error.message;
          _sources = const [];
        } else {
          _sources = (result as Success<List<PaymentSource>>).value;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل مصادر الإشعارات: $e';
        _sources = const [];
      });
    }
  }

  Future<void> _openAccess() async {
    await AppScope.of(context).notificationBridge.openAccessSettings();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _load();
  }

  Future<void> _syncFromWallets() async {
    final c = AppScope.of(context);
    final listed = await c.wallets.listAll();
    if (!mounted) return;
    if (listed is Failure<List<Wallet>>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            listed.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    var n = 0;
    for (final w in (listed as Success<List<Wallet>>).value) {
      final pkg = (w.packageName ?? '').trim();
      if (w.sourceMode != WalletSourceMode.notification || pkg.isEmpty) {
        continue;
      }
      final r = await c.notificationSources.upsert(
        displayName: w.name,
        packageName: pkg,
        enabled: true,
      );
      if (r is Success) n++;
    }
    try {
      await c.notificationHandler.refreshSources();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'لا محافظ بوضع إشعار وحزمة Android — أضفها من شاشة المحافظ'
              : 'تمت مزامنة $n مصدر من المحافظ',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
    await _load();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final package = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'إضافة مصدر محفظة',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'اسم المحفظة',
                  labelStyle: TextStyle(fontFamily: 'Tajawal'),
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: package,
                decoration: const InputDecoration(
                  labelText: 'اسم حزمة Android',
                  hintText: 'com.example.wallet',
                  labelStyle: TextStyle(fontFamily: 'Tajawal'),
                ),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              const SizedBox(height: 8),
              const Text(
                'لا نخمن أسماء الحزم. استخدم الاسم الفعلي للتطبيق على الجهاز.',
                style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final r = await AppScope.of(context).notificationSources.upsert(
          displayName: name.text.trim(),
          packageName: package.text.trim(),
          enabled: true,
        );
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _setEnabled(PaymentSource source, bool enabled) async {
    final pkg = source.packageName;
    if (pkg == null || pkg.isEmpty) return;
    final r = await AppScope.of(context).notificationSources.setEnabled(pkg, enabled);
    if (!mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.error.message,
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _remove(PaymentSource source) async {
    final pkg = source.packageName;
    if (pkg == null || pkg.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المصدر؟', style: TextStyle(fontFamily: 'Tajawal')),
          content: Text(
            'سيتم إيقاف قراءة إشعارات «${source.displayName}».',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).notificationSources.remove(pkg);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إشعارات المحافظ',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          actions: [
            TextButton(
              onPressed: _loading ? null : _syncFromWallets,
              child: const Text(
                'مزامنة المحافظ',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'مصدر جديد',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          ),
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
                            size: 28,
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'بدون هذا الإذن لن تُقرأ إشعارات تطبيقات المحافظ.',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _openAccess,
                            child: Text(
                              _accessGranted ? 'الإعدادات' : 'تفعيل',
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: NetSpacing.md),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NetSpacing.md),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            color: net.rejected,
                          ),
                        ),
                      ),
                    Text(
                      'المصادر المسجّلة (${_sources.length})',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: NetSpacing.sm),
                    if (_sources.isEmpty)
                      NetSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 40,
                              color: palette.textTertiary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لا مصادر إشعار بعد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'أضف مصدراً يدوياً، أو اضبط المحفظة على وضع «إشعار» مع حزمة Android ثم اضغط «مزامنة المحافظ».',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 13,
                                color: palette.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _syncFromWallets,
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text(
                                'مزامنة من المحافظ',
                                style: TextStyle(fontFamily: 'Tajawal'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final s in _sources)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NetSpacing.sm),
                          child: NetSurfaceCard(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: palette.primary,
                                ),
                                const SizedBox(width: NetSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.displayName,
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontWeight: FontWeight.w800,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        s.packageName ?? '—',
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 12,
                                          color: palette.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: s.enabled,
                                  onChanged: (v) => _setEnabled(s, v),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  onPressed: () => _remove(s),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 88),
                  ],
                ),
              ),
      ),
    );
  }
}
