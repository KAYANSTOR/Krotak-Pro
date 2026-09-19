import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import 'net_sparkline.dart';
import 'net_surface_card.dart';

/// بطاقة مؤشر لوحة التحكم (مبيعات اليوم / الشهر) — مطابقة للفيديو.
///
/// Adds an optional [sparkline] so trends are visible at a glance while the
/// title/value/subtitle contract stays identical for callers and tests.
class NetMetricCard extends StatelessWidget {
  const NetMetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.onTap,
    this.sparkline,
    this.accent,
    this.trailingLabel,
    this.selected = false,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  final List<double>? sparkline;
  final Color? accent;
  final String? trailingLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final tint = accent ?? palette.primary;
    final series = sparkline;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: NetRadii.mdAll,
        border: selected
            ? Border.all(color: tint, width: 1.6)
            : Border.all(color: Colors.transparent, width: 1.6),
      ),
      child: NetSurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.md,
          NetSpacing.md,
          NetSpacing.md,
          NetSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: palette.isDark ? 0.24 : 0.12),
                      borderRadius: NetRadii.xsAll,
                    ),
                    child: Icon(icon, size: 17, color: tint),
                  ),
                  const SizedBox(width: NetSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (trailingLabel != null)
                  Text(
                    trailingLabel!,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? tint : palette.textTertiary,
                    ),
                  )
                else if (onTap != null)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: NetSizes.iconSm,
                    color: palette.textTertiary,
                  ),
              ],
            ),
            const SizedBox(height: NetSpacing.md),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: palette.textPrimary,
              ),
            ),
            if (series != null && series.length > 1) ...[
              const SizedBox(height: NetSpacing.sm),
              NetSparkline(values: series, color: tint, height: 26),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: NetSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.sm,
                    vertical: NetSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: palette.isDark ? 0.22 : 0.10),
                    borderRadius: NetRadii.pillAll,
                  ),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
