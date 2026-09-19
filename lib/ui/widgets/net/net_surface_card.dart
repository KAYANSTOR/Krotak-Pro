import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// The single card surface used across NET screens.
///
/// Replaces the hand-rolled `Container(color: Colors.white, border: ...)`
/// pattern that broke dark mode, and keeps radius/border/elevation consistent.
class NetSurfaceCard extends StatelessWidget {
  const NetSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = NetSpacing.card,
    this.margin,
    this.radius = NetRadii.md,
    this.borderColor,
    this.color,
    this.elevated = false,
    this.glowColor,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? borderColor;
  final Color? color;
  final bool elevated;
  final Color? glowColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final resolvedGlow = glowColor;
    final shadows = resolvedGlow != null
        ? NetElevation.glow(resolvedGlow)
        : elevated
            ? NetElevation.raised(context)
            : null;

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadows,
        ),
        child: Material(
          color: color ?? palette.surface,
          clipBehavior: clipBehavior,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: borderColor ?? palette.border),
          ),
          child: onTap == null
              ? Padding(padding: padding, child: child)
              : InkWell(
                  onTap: onTap,
                  child: Padding(padding: padding, child: child),
                ),
        ),
      ),
    );
  }
}
