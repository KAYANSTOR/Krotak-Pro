import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import 'net_tab_header.dart';

/// ترويسة لوحة التحكم — اسم الشبكة هو العنوان الرئيسي في جهة البداية وأزرار
/// دائرية في الجهة المقابلة (تنبيهات · دعم · إعدادات) بهوية NET ومسمياتها.
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
    this.subscriptionLabel,
    this.remainingMessages,
    this.showGreeting = true,
  });

  final String networkName;
  final String dateLabel;

  /// تحية صغيرة فوق اسم الشبكة — تُخفى بتمرير [showGreeting] بقيمة false.
  final String? greeting;
  final VoidCallback? onSettings;
  final VoidCallback? onHelp;
  final VoidCallback? onNotifications;
  final int notificationsCount;

  /// شريط الاشتراك — يظهر دائمًا؛ القيمة الحقيقية أو «الاشتراك غير محدد».
  final String? subscriptionLabel;

  /// عدد الرسائل المتبقية (اختياري؛ null يخفي العنصر).
  final int? remainingMessages;

  /// اسم الشبكة هو العنوان الرئيسي؛ التحية سطر صغير اختياري فوقه.
  final bool showGreeting;

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
                if (showGreeting) ...[
                  Text(
                    greet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.15,
                    color: palette.textPrimary,
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
                const SizedBox(height: NetSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 13,
                      color: palette.primary,
                    ),
                    const SizedBox(width: NetSpacing.xs),
                    Flexible(
                      child: Text(
                        subscriptionLabel ?? 'الاشتراك غير محدد',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    if (remainingMessages != null) ...[
                      const SizedBox(width: NetSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.12),
                          borderRadius: NetRadii.pillAll,
                        ),
                        child: Text(
                          'الرسائل المتبقية: $remainingMessages',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: palette.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
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
