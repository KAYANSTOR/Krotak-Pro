import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';

class SalesCardsRow extends StatelessWidget {
  const SalesCardsRow({
    super.key,
    required this.dailyAmount,
    required this.dailyCards,
    required this.monthlyAmount,
    required this.monthlyCards,
    this.onDailyClick,
    this.onMonthlyClick,
  });

  final int dailyAmount;
  final int dailyCards;
  final int monthlyAmount;
  final int monthlyCards;
  final VoidCallback? onDailyClick;
  final VoidCallback? onMonthlyClick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _SalesCard(
              title: 'مبيعات اليوم',
              amount: dailyAmount,
              cardsCount: dailyCards,
              icon: Icons.trending_up,
              onTap: onDailyClick,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SalesCard(
              title: 'مبيعات الشهر',
              amount: monthlyAmount,
              cardsCount: monthlyCards,
              icon: Icons.calendar_today_outlined,
              onTap: onMonthlyClick,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({
    required this.title,
    required this.amount,
    required this.cardsCount,
    required this.icon,
    this.onTap,
  });

  final String title;
  final int amount;
  final int cardsCount;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KayanColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: KayanColors.borderGray),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: KayanColors.lightBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: KayanColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$amount',
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: KayanColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(
                      'ر.ي',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        color: KayanColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: KayanColors.lightBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$cardsCount كرت',
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: KayanColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
