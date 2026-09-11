import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';

/// Mirrors KayanBottomNavigation / DashboardBottomNavigation from Kotlin:
/// الرئيسية | التقارير | العروض | الحسابات | الكروت
class KayanBottomNav extends StatelessWidget {
  const KayanBottomNav({
    super.key,
    required this.currentId,
    required this.onSelect,
  });

  final String currentId;
  final ValueChanged<String> onSelect;

  static const items = [
    (id: 'dashboard', label: 'الرئيسية', icon: Icons.home_outlined, activeIcon: Icons.home),
    (id: 'reports', label: 'التقارير', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart),
    (id: 'offers', label: 'العروض', icon: Icons.local_offer_outlined, activeIcon: Icons.local_offer),
    (id: 'accounts', label: 'الحسابات', icon: Icons.people_outline, activeIcon: Icons.people),
    (id: 'cards', label: 'الكروت', icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KayanColors.surface,
        border: const Border(top: BorderSide(color: KayanColors.borderGray)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: _NavItem(
                  label: item.label,
                  icon: item.icon,
                  activeIcon: item.activeIcon,
                  active: currentId == item.id,
                  onTap: () => onSelect(item.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? KayanColors.primary : KayanColors.textSecondary;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: active ? KayanColors.lightBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(active ? activeIcon : icon, size: 22, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
