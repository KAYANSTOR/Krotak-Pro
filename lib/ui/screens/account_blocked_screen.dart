import 'package:flutter/material.dart';

import '../../application/account_session.dart';
import '../../core/app_brand.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_surface_card.dart';

/// شاشة تُعرض عندما توقف الإدارة الحساب أو تُدخل التطبيق في وضع الصيانة.
///
/// تُحدَّث تلقائياً عند إعادة التفعيل: زر «تحديث الحالة» يزامن مع الإدارة فوراً.
class AccountBlockedScreen extends StatefulWidget {
  const AccountBlockedScreen({super.key});

  @override
  State<AccountBlockedScreen> createState() => _AccountBlockedScreenState();
}

class _AccountBlockedScreenState extends State<AccountBlockedScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    final session = AccountSession.maybeInstance;
    if (session == null) return;
    setState(() => _busy = true);
    await session.sync(force: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text(
          'سيتم مسح بيانات الجلسة من هذا الجهاز، وستحتاج إلى إدخال رقم الهاتف وكلمة المرور مرة أخرى.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AccountSession.maybeInstance?.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final session = AccountSession.maybeInstance;

    return Scaffold(
      backgroundColor: palette.appBackground,
      body: SafeArea(
        child: session == null
            ? const SizedBox.shrink()
            : ValueListenableBuilder<AccountState>(
                valueListenable: session.state,
                builder: (context, state, _) {
                  final account = state.account;
                  final maintenance = !state.config.isAppActive;
                  final title =
                      maintenance ? 'التطبيق متوقف مؤقتاً' : 'هذا الحساب موقوف';
                  final message = state.message.isNotEmpty
                      ? state.message
                      : (maintenance
                          ? 'أوقفت الإدارة التطبيق مؤقتاً. سنعيده قريباً.'
                          : 'تواصل مع الإدارة لإعادة تفعيل حسابك.');

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      NetSpacing.lg,
                      NetSpacing.xxl,
                      NetSpacing.lg,
                      NetSpacing.xxl,
                    ),
                    children: [
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: net.errorContainer.withValues(
                              alpha: palette.isDark ? 0.55 : 1,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: net.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            maintenance
                                ? Icons.construction_rounded
                                : Icons.block_rounded,
                            size: 44,
                            color: net.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: NetSpacing.lg),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: NetSpacing.sm),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 13.5,
                          height: 1.6,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: NetSpacing.xl),
                      if (account != null)
                        NetSurfaceCard(
                          child: Column(
                            children: [
                              _row(context, 'اسم الشبكة',
                                  account.networkName.isEmpty ? '—' : account.networkName),
                              const SizedBox(height: NetSpacing.sm),
                              _row(context, 'رقم الهاتف', account.phone),
                              const SizedBox(height: NetSpacing.sm),
                              _row(context, 'حالة الحساب', account.statusLabel),
                            ],
                          ),
                        ),
                      if (state.offline) ...[
                        const SizedBox(height: NetSpacing.md),
                        Text(
                          'آخر حالة معروفة محفوظة على الجهاز — سيُحدَّث العرض عند عودة الإنترنت.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 11.5,
                            height: 1.5,
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                      const SizedBox(height: NetSpacing.xl),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _refresh,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: NetSizes.iconSm),
                          label: const Text('تحديث الحالة'),
                        ),
                      ),
                      const SizedBox(height: NetSpacing.sm),
                      OutlinedButton(
                        onPressed: _busy ? null : _signOut,
                        child: const Text('تسجيل الخروج'),
                      ),
                      const SizedBox(height: NetSpacing.xl),
                      Text(
                        '${AppBrand.name} · الإصدار ${AppBrand.version}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 11.5,
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final palette = KayanPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: NetSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
