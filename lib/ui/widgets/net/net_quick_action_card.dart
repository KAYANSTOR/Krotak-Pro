import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Horizontal quick-action tile (used by horizontal action rails).
class NetQuickActionCard extends StatelessWidget {
  const NetQuickActionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.width = 92,
    this.accent,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final double width;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final tint = accent ?? palette.primary;

    return Material(
      color: palette.surface,
      borderRadius: NetRadii.smAll,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: NetRadii.smAll,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(
            vertical: NetSpacing.md,
            horizontal: NetSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: NetRadii.smAll,
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: palette.isDark ? 0.22 : 0.12),
                  borderRadius: NetRadii.xsAll,
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(height: NetSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
