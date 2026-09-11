import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';

/// Placeholder until SalesReport / TransactionsLog / etc. are ported.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 48, color: KayanColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'التقارير',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: KayanColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'شاشات التقارير (المبيعات، نقاط البيع، السجل، الرسائل المرفوضة) لم تُنقل بعد من المرجع Kotlin.',
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
