import 'package:flutter/material.dart';


class CustomerBalanceCard extends StatelessWidget {
  const CustomerBalanceCard({
    super.key,
    required this.amount,
    required this.accounts,
    required this.cards,
    this.onCardStockClick,
  });

  final int amount;
  final int accounts;
  final int cards;
  final VoidCallback? onCardStockClick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A797A), Color(0xFFA4508B)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'إجمالي رصيد العملاء (المعلق)',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFE04096),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amount',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'ر.ي',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 20,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.2), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onCardStockClick,
                  child: Column(
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.white.withOpacity(0.8), size: 20),
                      const SizedBox(height: 4),
                      Text(
                        '$cards',
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'كروت متوفرة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withOpacity(0.2)),
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.people_outline, color: Colors.white.withOpacity(0.8), size: 20),
                    const SizedBox(height: 4),
                    Text(
                      '$accounts',
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'الحسابات',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
