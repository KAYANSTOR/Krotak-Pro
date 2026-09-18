import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import 'net_animated_counter.dart';

/// Customer outstanding balances card — Dashboard.
///
/// Title and semantics fixed by product decision:
/// إجمالي رصيد العملاء (المعلق) = sum of customer ledger balances (debt),
/// not network balance. Body has no tap; chips have separate actions.
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
      margin: const EdgeInsets.symmetric(horizontal: NetSpacing.lg, vertical: NetSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: [net.balanceGradientStart, net.balanceGradientEnd],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: NetElevation.glow(net.balanceGradientStart),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Decorative glow blobs keep the hero surface from looking flat.
            Positioned(
              top: -34,
              left: -24,
              child: _GlowBlob(
                size: 120,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            Positioned(
              bottom: -46,
              right: -18,
              child: _GlowBlob(
                size: 140,
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NetSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: NetSizes.iconSm,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Text(
                          'إجمالي رصيد العملاء (المعلق)',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.sm),
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
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: NetSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'ر.ي',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.18),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.md,
            vertical: NetSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: NetSizes.iconSm, color: Colors.white.withValues(alpha: 0.85)),
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
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: NetTypography.family,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
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
