import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';
import 'net_app_logo.dart';

/// ترويسة لوحة التحكم — مطابقة لفيديو Z Net.
class NetDashboardHeader extends StatelessWidget {
  const NetDashboardHeader({
    super.key,
    required this.networkName,
    required this.dateLabel,
    this.greeting,
    this.onSettings,
    this.onHelp,
  });

  final String networkName;
  final String dateLabel;
  final String? greeting;
  final VoidCallback? onSettings;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final displayName =
        networkName.trim().isEmpty ? 'NET' : networkName.trim();
    final greet = greeting ?? _defaultGreeting(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NetAppLogo(size: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'شبكة $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: KayanColors.primary,
                  ),
                ),
              ),
              if (onHelp != null)
                _RoundHeaderButton(
                  icon: Icons.help_outline_rounded,
                  tooltip: 'المساعدة',
                  onPressed: onHelp!,
                ),
              if (onSettings != null) ...[
                const SizedBox(width: 8),
                _RoundHeaderButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'الإعدادات',
                  onPressed: onSettings!,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$greet — $dateLabel',
            style: const TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: KayanColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _defaultGreeting(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'صباح الخير';
    return 'مساء الخير';
  }
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: KayanColors.borderGray),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: KayanColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

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
