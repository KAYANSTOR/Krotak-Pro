import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import 'net_app_logo.dart';
import 'net_tab_header.dart';

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
    final palette = KayanPalette.of(context);
    final displayName = networkName.trim().isEmpty ? 'NET' : networkName.trim();
    final greet = greeting ?? _defaultGreeting(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.sm,
        NetSpacing.lg,
        NetSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NetAppLogo(size: NetSizes.logo),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  'شبكة $displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: palette.primary,
                  ),
                ),
              ),
              if (onHelp != null)
                NetHeaderAction(
                  icon: Icons.help_outline_rounded,
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
          const SizedBox(height: NetSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: 14,
                color: palette.textTertiary,
              ),
              const SizedBox(width: NetSpacing.xs),
              Expanded(
                child: Text(
                  '$greet — $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13,
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
