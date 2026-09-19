import 'package:flutter/material.dart';

import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';

enum NetAlertStyle { warning, danger, info }

/// بانر تنبيه لوحة التحكم — يدعم نمط المخزون المنخفض (حدود حمراء) كالفيديو.
class NetAlertBanner extends StatelessWidget {
  const NetAlertBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.onTap,
    this.style = NetAlertStyle.warning,
    this.onDismiss,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onTap;
  final NetAlertStyle style;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    late final Color bg;
    late final Color fg;
    late final Color border;

    switch (style) {
      case NetAlertStyle.danger:
        bg = net.errorContainer;
        fg = net.rejected;
        border = net.error;
      case NetAlertStyle.warning:
        bg = net.alertBackground;
        fg = net.alertForeground;
        border = net.warning;
      case NetAlertStyle.info:
        bg = net.infoContainer;
        fg = net.info;
        border = net.info;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.lg,
        vertical: NetSpacing.xs,
      ),
      child: Material(
        color: bg,
        borderRadius: NetRadii.smAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: NetRadii.smAll,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: NetRadii.smAll,
              border: Border.all(color: border.withValues(alpha: 0.55), width: 1.2),
            ),
            child: Row(
              children: [
                Icon(icon, color: fg, size: NetSizes.iconSm),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12.5,
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  InkWell(
                    onTap: onDismiss,
                    borderRadius: NetRadii.pillAll,
                    child: Padding(
                      padding: const EdgeInsets.all(NetSpacing.xxs),
                      child: Icon(Icons.close_rounded, color: fg, size: 16),
                    ),
                  )
                else if (onTap != null)
                  Icon(Icons.chevron_left_rounded, color: fg, size: NetSizes.iconSm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
