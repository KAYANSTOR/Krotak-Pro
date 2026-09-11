import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';

/// Offers tab — Post-v1 product surface (not implemented).
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 48, color: KayanColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'العروض',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: KayanColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'ميزة العروض خارج نطاق الإصدار الحالي (Post-v1).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Tajawal',
                color: KayanColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
