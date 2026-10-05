import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/account_session.dart';
import '../../../core/contact_admin.dart';
import '../../../domain/entities/cloud_account.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../screens/settings/commission_billing_screen.dart';
import 'settings_section_header.dart';

/// بطاقة الحساب في الإعدادات — تصميم احترافي بهوية كروتك البصرية.
///
/// تعرض: هوية الشبكة (اسم + رقم + شارة الحالة)، حالة الاتصال والإشعارات،
/// ثم مسارات الإدارة: العمولات، اسم الشبكة، التواصل عبر واتساب، وتسجيل الخروج.
class AccountProfileCard extends StatelessWidget {
  const AccountProfileCard({
    super.key,
    required this.networkName,
    required this.onEditNetworkName,
    required this.onSignOut,
  });

  /// اسم الشبكة المحفوظ في الإعدادات (يُستخدم عند تأخر وصول بيانات الحساب).
  final String networkName;
  final Future<void> Function() onEditNetworkName;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final session = AccountSession.maybeInstance;
    if (session == null) return const SizedBox.shrink();

    return ValueListenableBuilder<AccountState>(
      valueListenable: session.state,
      builder: (context, state, _) {
        final account = state.account;
        if (account == null && state.phase != AccountPhase.blocked) {
          return const SizedBox.shrink();
        }
        final displayName = (account?.networkName.isNotEmpty == true)
            ? account!.networkName
            : (networkName.trim().isNotEmpty
                ? networkName.trim()
                : 'حساب الشبكة');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SettingsSectionHeader(title: 'الحساب'),
            _ProfileHero(
              displayName: displayName,
              account: account,
              offline: state.offline,
            ),
            const SizedBox(height: NetSpacing.sm),
            _ProfileFacts(account: account, unread: state.unreadCount),
            const SizedBox(height: NetSpacing.sm),
            _ProfileActions(
              onEditNetworkName: onEditNetworkName,
              onSignOut: onSignOut,
            ),
          ],
        );
      },
    );
  }
}

// ── الترويسة: هوية الشبكة + شارة الحالة ────────────────────────────────

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.displayName,
    required this.account,
    required this.offline,
  });

  final String displayName;
  final CloudAccount? account;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final base = palette.primary;
    final deep = Color.lerp(base, Colors.black, palette.isDark ? 0.34 : 0.22)!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NetRadii.lg),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [base, deep],
        ),
        boxShadow: NetElevation.glow(base, opacity: palette.isDark ? 0.22 : 0.3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // زخرفة خلفية خفيفة — دائرتان شفافتان بنفس هوية الهوية البصرية.
          PositionedDirectional(
            top: -46,
            end: -30,
            child: _Glow(size: 132, color: Colors.white.withValues(alpha: 0.10)),
          ),
          PositionedDirectional(
            bottom: -58,
            start: -26,
            child: _Glow(size: 118, color: Colors.white.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NetSpacing.lg,
              NetSpacing.lg,
              NetSpacing.lg,
              NetSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ProfileAvatar(),
                    const SizedBox(width: NetSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              height: 1.2,
                              color: palette.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'لوحة إدارة شبكة الكروت',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: palette.onPrimary.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(height: NetSpacing.sm),
                          Wrap(
                            spacing: NetSpacing.xs,
                            runSpacing: NetSpacing.xs,
                            children: [
                              _StatusPill(
                                label: _statusLabel(account),
                                icon: _statusIcon(account),
                                tone: _statusTone(account),
                              ),
                              if (offline)
                                _StatusPill(
                                  label: 'بلا إنترنت',
                                  icon: Icons.cloud_off_rounded,
                                  tone: const Color(0xFFF59E0B),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NetSpacing.md),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: palette.onPrimary.withValues(alpha: 0.18),
                ),
                const SizedBox(height: NetSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(
                        label: 'رقم الحساب',
                        value: _phoneLabel(account),
                        icon: Icons.badge_outlined,
                        onPrimary: palette.onPrimary,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      color: palette.onPrimary.withValues(alpha: 0.18),
                    ),
                    Expanded(
                      child: _HeroMetric(
                        label: 'الاشتراك',
                        value: _subscriptionLabel(account),
                        icon: Icons.verified_user_outlined,
                        onPrimary: palette.onPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _phoneLabel(CloudAccount? account) {
    final phone = account?.phone ?? '';
    return phone.isEmpty ? 'غير محدد' : phone;
  }

  static String _subscriptionLabel(CloudAccount? account) {
    if (account == null) return 'غير متاح';
    final remaining = account.remainingDays;
    if (remaining == null) return account.isActive ? 'دائم' : 'موقوف';
    if (remaining < 0) return 'منتهي';
    if (remaining == 0) return 'ينتهي اليوم';
    return 'متبقٍ $remaining يوم';
  }

  static String _statusLabel(CloudAccount? account) {
    if (account == null) return 'الحساب موقوف';
    if (!account.isActive) return 'موقوف من الإدارة';
    if (account.isTrial) return 'حساب تجريبي';
    return 'حساب نشط';
  }

  static IconData _statusIcon(CloudAccount? account) {
    if (account == null || !account.isActive) return Icons.block_rounded;
    if (account.isTrial) return Icons.hourglass_bottom_rounded;
    return Icons.verified_rounded;
  }

  static Color _statusTone(CloudAccount? account) {
    if (account == null || !account.isActive) return const Color(0xFFDC2626);
    if (account.isTrial) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// صورة الهوية: شعار التطبيق من الأصل المدمج، مع بديل آمن عند تعذّر التحميل.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(NetRadii.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<String>(
        future: rootBundle.loadString('assets/icon/krotak_icon.b64'),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            try {
              return Image.memory(
                base64Decode(snapshot.data!.trim()),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            } catch (_) {
              // أصل تالف — نكمل بالبديل الرمزي.
            }
          }
          return const Icon(
            Icons.storefront_rounded,
            color: Color(0xFFE27A55),
            size: 30,
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: NetRadii.pillAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onPrimary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color onPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: onPrimary.withValues(alpha: 0.78)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: onPrimary.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: onPrimary,
          ),
        ),
      ],
    );
  }
}

// ── الحقائق: صفوف معلومات داخل بطاقة سطح موحّدة ─────────────────────────

class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({required this.account, required this.unread});

  final CloudAccount? account;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final rows = <Widget>[
      _FactRow(
        icon: Icons.sim_card_outlined,
        label: 'رقم الحساب المسجّل',
        value: (account?.phone ?? '').isEmpty ? 'غير محدد' : account!.phone,
      ),
      _FactRow(
        icon: Icons.payments_outlined,
        label: 'نسبة العمولة',
        value: account?.commissionRate == null
            ? 'حسب إعداد الإدارة'
            : '${_formatRate(account!.commissionRate!)}%',
      ),
      _FactRow(
        icon: Icons.notifications_none_rounded,
        label: 'إشعارات الإدارة',
        value: unread == 0 ? 'لا إشعارات جديدة' : '$unread غير مقروء',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(NetRadii.md),
        border: Border.all(color: palette.border),
        boxShadow: NetElevation.soft(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: palette.border),
            rows[i],
          ],
        ],
      ),
    );
  }

  static String _formatRate(double rate) {
    if (rate == rate.roundToDouble()) return rate.toInt().toString();
    return rate.toStringAsFixed(2);
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.md,
        vertical: NetSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Icon(icon, size: NetSizes.iconSm, color: palette.primary),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── الإجراءات ─────────────────────────────────────────────────────────

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.onEditNetworkName,
    required this.onSignOut,
  });

  final Future<void> Function() onEditNetworkName;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionTile(
          icon: Icons.percent_rounded,
          title: 'العمولات والمبيعات',
          subtitle: 'كشف الحساب ونسب العمولة والمطالبات',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CommissionBillingScreen(),
            ),
          ),
        ),
        const SizedBox(height: NetSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.storefront_outlined,
                title: 'اسم الشبكة',
                subtitle: 'يظهر في الرسائل',
                onTap: () => onEditNetworkName(),
              ),
            ),
            const SizedBox(width: NetSpacing.sm),
            Expanded(
              child: _ActionTile(
                icon: Icons.chat_rounded,
                title: 'الإدارة',
                subtitle: 'واتساب',
                tone: net.available,
                onTap: () => AdminContact.openWhatsApp(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: NetSpacing.sm),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(NetRadii.md),
            onTap: () => onSignOut(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: NetSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NetRadii.md),
                border: Border.all(color: net.rejected.withValues(alpha: 0.45)),
                color: net.rejected.withValues(alpha: 0.06),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: NetSizes.iconSm, color: net.rejected),
                  const SizedBox(width: NetSpacing.sm),
                  Text(
                    'تسجيل الخروج من الحساب',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: net.rejected,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'بياناتك المحلية (الكروت والمبيعات والحسابات) لا تُمس عند الخروج.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 10.5,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final accent = tone ?? palette.primary;

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(NetRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(NetRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(NetSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NetRadii.md),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: palette.isDark ? 0.22 : 0.12),
                  borderRadius: NetRadii.smAll,
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                size: NetSizes.iconMd,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
