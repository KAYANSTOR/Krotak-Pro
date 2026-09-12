import 'package:flutter/material.dart';

import 'net_app_logo.dart';

/// Dashboard top bar — product decision PD-2026-09-12-02.
///
/// Shows only: logo + network name, weekday/date, settings, help.
/// No license, SMS, or other operational subtitle.
class NetDashboardHeader extends StatelessWidget {
  const NetDashboardHeader({
    super.key,
    required this.networkName,
    required this.dateLabel,
    this.onSettings,
    this.onHelp,
  });

  /// Display name of the network (from settings, default NET).
  final String networkName;

  /// Pre-formatted Arabic date with weekday (e.g. السبت، 12 سبتمبر).
  final String dateLabel;

  final VoidCallback? onSettings;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NetAppLogo(size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  networkName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: cs.primary,
                  ),
                ),
              ),
              if (onHelp != null)
                _HeaderIconButton(
                  icon: Icons.help_outline,
                  tooltip: 'المساعدة',
                  onPressed: onHelp!,
                ),
              if (onSettings != null) ...[
                const SizedBox(width: 4),
                _HeaderIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'الإعدادات',
                  onPressed: onSettings!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withOpacity(0.65),
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: cs.onSurface, size: 22),
      ),
    );
  }
}

/// Formats [date] as Arabic weekday + day + month (no intl dependency).
String formatArabicDashboardDate(DateTime date) {
  const weekdays = <String>[
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  const months = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  final weekday = weekdays[(date.weekday - 1) % 7];
  final month = months[(date.month - 1) % 12];
  return '$weekday، ${date.day} $month';
}
