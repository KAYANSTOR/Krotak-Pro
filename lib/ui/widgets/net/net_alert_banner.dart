import 'package:flutter/material.dart';
import '../../theme/net_semantic_colors.dart';

class NetAlertBanner extends StatelessWidget {
  const NetAlertBanner({super.key, required this.message, this.icon = Icons.info_outline, this.onTap});
  final String message;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final net = context.netColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: net.alertBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: net.alertForeground, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(message, style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, color: net.alertForeground, fontWeight: FontWeight.w600))),
                if (onTap != null) Icon(Icons.chevron_left, color: net.alertForeground, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
