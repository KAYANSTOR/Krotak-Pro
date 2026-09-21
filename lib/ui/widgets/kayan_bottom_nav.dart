import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';

/// شريط تنقل سفلي بشكل التطبيق المرجعي: أربعة عناصر مسطّحة وزر وسطي بارز
/// للإجراءات السريعة، مع مسميات NET وألوانها.
///
/// العناصر: الرئيسية | الحسابات | (الإجراءات) | التقارير | الكروت
class KayanBottomNav extends StatelessWidget {
  const KayanBottomNav({
    super.key,
    required this.currentId,
    required this.onSelect,
    this.onQuickActions,
    this.quickActionsLabel = 'الإجراءات',
    this.attentionCount = 0,
  });

  final String currentId;
  final ValueChanged<String> onSelect;

  /// Opens the quick-actions sheet; when null the center button is hidden.
  final VoidCallback? onQuickActions;
  final String quickActionsLabel;

  /// عدد الرسائل التي تحتاج تدخلاً — شارة على تبويب الرئيسية.
  final int attentionCount;

  /// Visible bar items. العروض يبقى شاشة كاملة ويُفتح من لوحة التحكم
  /// أو من ورقة الإجراءات السريعة.
  static const items = [
    (id: 'dashboard', label: 'الرئيسية', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    (id: 'accounts', label: 'الحسابات', icon: Icons.groups_outlined, activeIcon: Icons.groups_rounded),
    (id: 'reports', label: 'التقارير', icon: Icons.insights_outlined, activeIcon: Icons.insights_rounded),
    (id: 'cards', label: 'الكروت', icon: Icons.style_outlined, activeIcon: Icons.style_rounded),
  ];

  static const double _centerSlot = 72;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final left = items.sublist(0, items.length ~/ 2);
    final right = items.sublist(items.length ~/ 2);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: NetElevation.soft(context),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    for (final item in left) ...[
                      Expanded(
                        child: _NavItem(
                          key: ValueKey('nav-${item.id}'),
                          label: item.label,
                          icon: item.icon,
                          activeIcon: item.activeIcon,
                          active: currentId == item.id,
                          badgeCount: item.id == 'dashboard' ? attentionCount : 0,
                          onTap: () => onSelect(item.id),
                        ),
                      ),
                    ],
                    SizedBox(width: onQuickActions == null ? 0 : _centerSlot),
                    for (final item in right)
                      Expanded(
                        child: _NavItem(
                          key: ValueKey('nav-${item.id}'),
                          label: item.label,
                          icon: item.icon,
                          activeIcon: item.activeIcon,
                          active: currentId == item.id,
                          badgeCount: 0,
                          onTap: () => onSelect(item.id),
                        ),
                      ),
                  ],
                ),
              ),
              if (onQuickActions != null)
                Positioned(
                  top: -24,
                  child: _QuickActionsButton(
                    label: quickActionsLabel,
                    onTap: onQuickActions!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsButton extends StatelessWidget {
  const _QuickActionsButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: palette.surface,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(5),
          child: Material(
            key: const ValueKey('nav-quick-actions'),
            color: palette.primary,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: palette.primary.withValues(alpha: 0.45),
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              customBorder: const CircleBorder(),
              child: Icon(
                Icons.add_rounded,
                size: 27,
                color: palette.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: palette.textSecondary,
          ),
        ),
      ],
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
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  /// شارة عدد (0 = بلا شارة).
  final int badgeCount;

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
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: duration,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.md,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? palette.primary.withValues(
                            alpha: palette.isDark ? 0.22 : 0.10,
                          )
                        : Colors.transparent,
                    borderRadius: NetRadii.pillAll,
                  ),
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: NetMotion.standard,
                    child: Icon(
                      active ? activeIcon : icon,
                      key: ValueKey(active),
                      size: 23,
                      color: color,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    left: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.netColors.error,
                        borderRadius: NetRadii.pillAll,
                        border: Border.all(color: palette.surface, width: 1.4),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 10,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: palette.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NetSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 11,
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
