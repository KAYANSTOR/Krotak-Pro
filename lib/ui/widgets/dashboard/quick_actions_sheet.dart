import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// ورقة الإجراءات السريعة — تُفتح من الزر الوسطي في الشريط السفلي.
///
/// إجراءان فقط كما في التصميم المرجعي: البيع المباشر وإضافة عميل.
/// لا تنفّذ شيئًا بنفسها: تستدعي الـcallbacks الممرّرة فقط.
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.onDirectSale,
    required this.onAddCustomer,
  });

  final VoidCallback onDirectSale;
  final VoidCallback onAddCustomer;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDirectSale,
    required VoidCallback onAddCustomer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => QuickActionsSheet(
        onDirectSale: onDirectSale,
        onAddCustomer: onAddCustomer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

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
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.point_of_sale_rounded,
                    label: 'بيع مباشر',
                    hint: 'بيع كرت فورًا',
                    onTap: () {
                      Navigator.of(context).pop();
                      onDirectSale();
                    },
                  ),
                ),
                const SizedBox(width: NetSpacing.sm),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.person_add_alt_rounded,
                    label: 'إضافة عميل',
                    hint: 'حساب عميل جديد',
                    onTap: () {
                      Navigator.of(context).pop();
                      onAddCustomer();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
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
          padding: const EdgeInsets.all(NetSpacing.md),
          child: Column(
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
                child: Icon(icon, color: palette.primary),
              ),
              const SizedBox(height: NetSpacing.sm),
              Text(
                label,
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
                hint,
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
