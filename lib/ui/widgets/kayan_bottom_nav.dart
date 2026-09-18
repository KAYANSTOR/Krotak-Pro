import 'package:flutter/material.dart';

import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';

/// شريط تنقل سفلي: الرئيسية | التقارير | العروض | الحسابات | الكروت
class KayanBottomNav extends StatelessWidget {
  const KayanBottomNav({
    super.key,
    required this.currentId,
    required this.onSelect,
  });

  final String currentId;
  final ValueChanged<String> onSelect;

  static const items = [
    (id: 'dashboard', label: 'الرئيسية', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    (id: 'reports', label: 'التقارير', icon: Icons.insights_outlined, activeIcon: Icons.insights_rounded),
    (id: 'offers', label: 'العروض', icon: Icons.local_offer_outlined, activeIcon: Icons.local_offer_rounded),
    (id: 'accounts', label: 'الحسابات', icon: Icons.groups_outlined, activeIcon: Icons.groups_rounded),
    (id: 'cards', label: 'الكروت', icon: Icons.style_outlined, activeIcon: Icons.style_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final kayan = KayanPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: kayan.surface,
        border: Border(top: BorderSide(color: kayan.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: _NavItem(
                  key: ValueKey('nav-${item.id}'),
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
    super.key,
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
    final kayan = KayanPalette.of(context);
    final color = active ? KayanColors.primary : kayan.textSecondary;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? KayanColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(active ? activeIcon : icon, size: 22, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 11.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
