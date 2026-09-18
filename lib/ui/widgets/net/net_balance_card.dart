import 'package:flutter/material.dart';

import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import 'net_animated_counter.dart';

/// Customer outstanding balances card — Dashboard.
///
/// Title and semantics fixed by product decision:
/// إجمالي رصيد العملاء (المعلق) = sum of customer ledger balances (debt),
/// not network balance. Body has no tap; chips have separate actions.
///
/// البصريات فقط: تدرّج أعمق، لمعة ذهبية محدودة، وفواصل أوضح — بلا أي تغيير
/// في القيم أو الإجراءات.
class NetBalanceCard extends StatelessWidget {
  const NetBalanceCard({
    super.key,
    required this.balanceMinor,
    required this.accountsCount,
    required this.availableCards,
    this.onTapAccounts,
    this.onTapCards,
    this.animateAmount = true,
  });

  final int balanceMinor;
  final int accountsCount;
  final int availableCards;
  final VoidCallback? onTapAccounts;
  final VoidCallback? onTapCards;
  final bool animateAmount;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    final radius = BorderRadius.circular(NetRadii.xl);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.md,
        NetSpacing.lg,
        NetSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: [
            net.balanceGradientStart,
            Color.lerp(net.balanceGradientStart, net.balanceGradientEnd, 0.55)!,
            net.balanceGradientEnd,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: NetElevation.glow(net.balanceGradientStart, opacity: 0.30),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Deepening wash keeps the hero surface readable in both themes.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            // Decorative glow blobs keep the hero surface from looking flat.
            Positioned(
              top: -46,
              left: -30,
              child: _GlowBlob(
                size: 150,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              top: 14,
              left: 30,
              child: _Ring(size: 84, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Positioned(
              bottom: -54,
              right: -22,
              child: _GlowBlob(
                size: 150,
                color: Colors.black.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NetSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: NetRadii.xsAll,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Text(
                          'إجمالي رصيد العملاء (المعلق)',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: NetAnimatedCounter(
                          valueMinor: balanceMinor,
                          animate: animateAmount,
                          style: const TextStyle(
                            fontFamily: NetTypography.family,
                            color: Colors.white,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.4,
                            shadows: [
                              Shadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: NetSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NetSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: NetRadii.pillAll,
                          ),
                          child: Text(
                            'ر.ي',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  // Limited gold accent: a short accent bar, not a full gold rule.
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 3,
                        decoration: BoxDecoration(
                          color: net.premium,
                          borderRadius: NetRadii.pillAll,
                        ),
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _chip(
                          label: 'الحسابات',
                          value: '$accountsCount',
                          icon: Icons.groups_rounded,
                          onTap: onTapAccounts,
                        ),
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: _chip(
                          label: 'كروت متوفرة',
                          value: '$availableCards',
                          icon: Icons.style_rounded,
                          onTap: onTapCards,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.sm),
                  // شريط تقدم ذهبي رقيق — لمسة فاخرة محدودة تعكس امتلاء الخدمة.
                  ClipRRect(
                    borderRadius: NetRadii.pillAll,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: availableCards > 0 ? 0.68 : 0.18),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) => LinearProgressIndicator(
                        value: t.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        valueColor: AlwaysStoppedAnimation<Color>(net.premium),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: NetRadii.smAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: NetRadii.smAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.md,
            vertical: NetSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: NetRadii.smAll,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(icon, size: NetSizes.iconSm, color: Colors.white.withValues(alpha: 0.92)),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: NetTypography.family,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                size: NetSizes.iconSm,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 10),
      ),
    );
  }
}
