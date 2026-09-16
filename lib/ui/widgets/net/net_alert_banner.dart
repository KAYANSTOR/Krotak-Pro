import 'package:flutter/material.dart';

import '../../theme/net_semantic_colors.dart';

enum NetAlertStyle { warning, danger, info }

/// بانر تنبيه لوحة التحكم — يدعم نمط المخزون المنخفض (حدود حمراء) كالفيديو.
class NetAlertBanner extends StatelessWidget {
  const NetAlertBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.onTap,
    this.style = NetAlertStyle.warning,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onTap;
  final NetAlertStyle style;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    late final Color bg;
    late final Color fg;
    late final Color border;

    switch (style) {
      case NetAlertStyle.danger:
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFBE123C);
        border = const Color(0xFFFB7185);
      case NetAlertStyle.warning:
        bg = net.alertBackground;
        fg = net.alertForeground;
        border = const Color(0xFFFCD34D);
      case NetAlertStyle.info:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        border = const Color(0xFF93C5FD);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_left, color: fg, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
