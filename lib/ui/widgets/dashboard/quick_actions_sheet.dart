import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// ورقة الإجراءات السريعة — تُفتح من الزر الوسطي في الشريط السفلي.
///
/// كانت إجراءين فقط (بيع مباشر/إضافة عميل) فأصبحت شبكة 2×3 تغطي أكثر المسارات
/// استخدامًا في العمل اليومي: البيع، العميل، نقاط البيع، توليد الكروت، رسالة
/// جماعية، وتقارير اليوم. لا تنفّذ شيئًا بنفسها: تستدعي الـcallbacks فقط، وأي
/// callback غائب لا يُعرض كرته.
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.onDirectSale,
    required this.onAddCustomer,
    this.onPos,
    this.onGenerateCards,
    this.onBroadcast,
    this.onTodayReports,
  });

  final VoidCallback onDirectSale;
  final VoidCallback onAddCustomer;
  final VoidCallback? onPos;
  final VoidCallback? onGenerateCards;
  final VoidCallback? onBroadcast;
  final VoidCallback? onTodayReports;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDirectSale,
    required VoidCallback onAddCustomer,
    VoidCallback? onPos,
    VoidCallback? onGenerateCards,
    VoidCallback? onBroadcast,
    VoidCallback? onTodayReports,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => QuickActionsSheet(
        onDirectSale: onDirectSale,
        onAddCustomer: onAddCustomer,
        onPos: onPos,
        onGenerateCards: onGenerateCards,
        onBroadcast: onBroadcast,
        onTodayReports: onTodayReports,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.point_of_sale_rounded,
        label: 'بيع مباشر',
        hint: 'بيع كرت فورًا',
        onTap: onDirectSale,
      ),
      _QuickAction(
        icon: Icons.person_add_alt_rounded,
        label: 'إضافة عميل',
        hint: 'حساب عميل جديد',
        onTap: onAddCustomer,
      ),
      if (onPos != null)
        _QuickAction(
          icon: Icons.storefront_rounded,
          label: 'نقاط البيع',
          hint: 'الحسابات والقوالب',
          onTap: onPos!,
        ),
      if (onGenerateCards != null)
        _QuickAction(
          icon: Icons.style_rounded,
          label: 'توليد كروت',
          hint: 'إضافة مخزون',
          onTap: onGenerateCards!,
        ),
      if (onBroadcast != null)
        _QuickAction(
          icon: Icons.campaign_rounded,
          label: 'رسالة جماعية',
          hint: 'إلى مجموعة عملاء',
          onTap: onBroadcast!,
        ),
      if (onTodayReports != null)
        _QuickAction(
          icon: Icons.insights_rounded,
          label: 'تقارير اليوم',
          hint: 'مبيعات وحوالات',
          onTap: onTodayReports!,
        ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: NetRadii.sheetTop,
          boxShadow: NetElevation.raised(context),
        ),
        padding: EdgeInsets.fromLTRB(
          NetSpacing.xl,
          NetSpacing.sm,
          NetSpacing.xl,
          NetSpacing.xl + bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: NetSpacing.lg),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: NetRadii.pillAll,
                ),
              ),
            ),
            Text(
              'إجراءات سريعة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.lg),
            for (var i = 0; i < actions.length; i += 2) ...[
              if (i > 0) const SizedBox(height: NetSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        action: actions[i],
                        onTap: () {
                          Navigator.of(context).pop();
                          actions[i].onTap();
                        },
                      ),
                    ),
                    const SizedBox(width: NetSpacing.sm),
                    Expanded(
                      child: i + 1 < actions.length
                          ? _QuickActionCard(
                              action: actions[i + 1],
                              onTap: () {
                                Navigator.of(context).pop();
                                actions[i + 1].onTap();
                              },
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action, required this.onTap});

  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Material(
      color: palette.surfaceVariant,
      borderRadius: NetRadii.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: NetRadii.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NetSpacing.md,
            vertical: NetSpacing.md,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(
                    alpha: palette.isDark ? 0.24 : 0.12,
                  ),
                  borderRadius: NetRadii.smAll,
                ),
                child: Icon(action.icon, color: palette.primary),
              ),
              const SizedBox(height: NetSpacing.sm),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: NetSpacing.xxs),
              Text(
                action.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
