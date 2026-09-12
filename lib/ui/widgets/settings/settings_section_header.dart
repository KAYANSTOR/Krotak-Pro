import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';

/// Section title used inside Settings hub (PD-07 Q7).
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: KayanColors.textPrimary,
        ),
      ),
    );
  }
}
