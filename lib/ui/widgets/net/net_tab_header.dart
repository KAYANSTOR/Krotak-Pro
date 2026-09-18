import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Unified header for the five main tabs (and any screen that does not use an
/// [AppBar]): icon badge + title + optional subtitle + circular actions.
///
/// Replaces the previous mix of a shell [AppBar] plus duplicated in-body titles.
class NetTabHeader extends StatelessWidget {
  const NetTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      NetSpacing.lg,
      NetSpacing.sm,
      NetSpacing.lg,
      NetSpacing.md,
    ),
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: NetSizes.badge,
                  height: NetSizes.badge,
                  decoration: BoxDecoration(
                    color: palette.iconBadgeBackground,
                    borderRadius: NetRadii.smAll,
                  ),
                  child: Icon(icon, size: 20, color: palette.primary),
                ),
                const SizedBox(width: NetSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 12.5,
                          height: 1.35,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              ...actions,
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: palette.border),
      ],
    );
  }
}

/// Compact circular icon action used inside [NetTabHeader].
class NetHeaderAction extends StatelessWidget {
  const NetHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badgeCount = 0,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int badgeCount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final tint = color ?? palette.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: NetSpacing.sm),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: NetRadii.smAll,
          side: BorderSide(color: palette.border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: NetRadii.smAll,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: NetSizes.iconMd, color: tint),
                  if (badgeCount > 0)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: NetRadii.pillAll,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
