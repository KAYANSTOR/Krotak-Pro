import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

class NetSectionHeader extends StatelessWidget {
  const NetSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      NetSpacing.xl,
      NetSpacing.lg,
      NetSpacing.lg,
      NetSpacing.sm,
    ),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(left: NetSpacing.sm),
            decoration: BoxDecoration(
              color: palette.primary,
              borderRadius: NetRadii.pillAll,
            ),
          ),
          if (icon != null) ...[
            Icon(icon, size: NetSizes.iconSm, color: palette.primary),
            const SizedBox(width: NetSpacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: NetSpacing.sm),
                minimumSize: const Size(NetSpacing.touchTarget, 36),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.primary,
                    ),
                  ),
                  const SizedBox(width: NetSpacing.xxs),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: NetSizes.iconSm,
                    color: palette.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
