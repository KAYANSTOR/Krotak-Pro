import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';

/// Section title used inside Settings hub (matches Z Net video teal labels).
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: KayanColors.primary,
        ),
      ),
    );
  }
}
