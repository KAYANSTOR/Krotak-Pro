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

/// بطاقة خدمة كبيرة — 2×2 على الرئيسية: أيقونة كبيرة في شارة ملوّنة، اسم بارز،
/// ووصف قصير. نفس لغة التصميم العامة بحجم أضخم ليناسب الشاشة.
class NetServiceBigTile extends StatelessWidget {
  const NetServiceBigTile({
    super.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
    this.tint,
    this.badgeCount = 0,
  });

  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  /// لون الأيقونة والشارة؛ الافتراضي أساس الهوية.
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
          padding: const EdgeInsets.all(NetSpacing.md),
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
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: NetRadii.smAll,
                    ),
                    child: Icon(icon, size: 30, color: color),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -7,
                      left: -10,
                      child: _ServiceBadge(count: badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: NetSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                textAlign: TextAlign.center,
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
      ),
    );
  }
}

/// شبكة 2×2 لبطاقات الخدمات الكبيرة على الرئيسية.
class NetServiceBigGrid extends StatelessWidget {
  const NetServiceBigGrid({
    super.key,
    required this.tiles,
    this.padding = NetSpacing.pageH,
  });

  final List<Widget> tiles;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: NetSpacing.sm,
        crossAxisSpacing: NetSpacing.sm,
        // نسبة قصيرة نسبيًا حتى لا يتجاوز محتوى البطاقة الشاشات الضيقة.
        childAspectRatio: 1.05,
        children: tiles,
      ),
    );
  }
}
