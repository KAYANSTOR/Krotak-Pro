import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';

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
    final palette = KayanPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: NetElevation.soft(context),
      ),
      padding: const EdgeInsets.only(top: NetSpacing.sm, bottom: NetSpacing.sm),
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
    final palette = KayanPalette.of(context);
    final color = active ? palette.primary : palette.textSecondary;
    final duration = NetMotion.scale(context, NetDurations.fast);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NetSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: duration,
              curve: NetMotion.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: NetSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? palette.primary.withValues(alpha: palette.isDark ? 0.20 : 0.12)
                    : Colors.transparent,
                borderRadius: NetRadii.pillAll,
              ),
              child: AnimatedSize(
                duration: duration,
                curve: NetMotion.standard,
                child: Icon(
                  active ? activeIcon : icon,
                  size: active ? 23 : 22,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
