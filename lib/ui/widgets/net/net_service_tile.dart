import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';

/// One tile of the home-screen services grid.
///
/// Presentation only: the caller decides which product destination the tile
/// opens and which semantic tint it uses. The shape follows the reference home
/// layout (flat surface card, line icon, centered label) while colors, labels
/// and icons stay the ones NET already uses elsewhere.
class NetServiceTile extends StatelessWidget {
  const NetServiceTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Icon tint; defaults to the brand primary.
  final Color? tint;

  /// Optional attention count rendered as a small pill (0 hides it).
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final color = tint ?? palette.primary;

    return Material(
      color: palette.surface,
      borderRadius: NetRadii.mdAll,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: NetRadii.mdAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.sm,
            vertical: NetSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: NetRadii.mdAll,
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 27, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      top: -7,
                      left: -14,
                      child: _ServiceBadge(count: badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: NetSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
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

class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final color = context.netColors.rejected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: NetRadii.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 3-column services grid used on the home screen.
class NetServiceGrid extends StatelessWidget {
  const NetServiceGrid({
    super.key,
    required this.tiles,
    this.columns = 3,
    this.padding = NetSpacing.pageH,
  });

  final List<Widget> tiles;
  final int columns;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisSpacing: NetSpacing.sm,
        crossAxisSpacing: NetSpacing.sm,
        childAspectRatio: 1.02,
        children: tiles,
      ),
    );
  }
}
