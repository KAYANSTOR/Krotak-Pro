import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import 'net_tab_header.dart';

/// ترويسة لوحة التحكم — ترحيب بارز في جهة البداية وأزرار دائرية في الجهة
/// المقابلة (تنبيهات · دعم · إعدادات) بهوية NET ومسمياتها.
class NetDashboardHeader extends StatelessWidget {
  const NetDashboardHeader({
    super.key,
    required this.networkName,
    required this.dateLabel,
    this.greeting,
    this.onSettings,
    this.onHelp,
    this.onNotifications,
    this.notificationsCount = 0,
  });

  final String networkName;
  final String dateLabel;
  final String? greeting;
  final VoidCallback? onSettings;
  final VoidCallback? onHelp;
  final VoidCallback? onNotifications;
  final int notificationsCount;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final displayName = networkName.trim().isEmpty ? 'NET' : networkName.trim();
    final greet = greeting ?? _defaultGreeting(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.md,
        NetSpacing.lg,
        NetSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 21,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: NetSpacing.xxs),
                Text(
                  'شبكة $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          if (onNotifications != null)
            NetHeaderAction(
              icon: Icons.notifications_none_rounded,
              tooltip: 'التنبيهات',
              badgeCount: notificationsCount,
              onPressed: onNotifications,
            ),
          if (onHelp != null)
            NetHeaderAction(
              icon: Icons.support_agent_rounded,
              tooltip: 'المساعدة',
              onPressed: onHelp,
            ),
          if (onSettings != null)
            NetHeaderAction(
              icon: Icons.settings_outlined,
              tooltip: 'الإعدادات',
              onPressed: onSettings,
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
