import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Section title used inside Settings hub (matches Z Net video teal labels).
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.xs,
        NetSpacing.lg,
        NetSpacing.xs,
        NetSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: NetSizes.iconSm, color: palette.primary),
            const SizedBox(width: NetSpacing.sm),
          ],
          Text(
            title,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: palette.primary,
            ),
          ),
        ],
      ),
    );
  }
}
