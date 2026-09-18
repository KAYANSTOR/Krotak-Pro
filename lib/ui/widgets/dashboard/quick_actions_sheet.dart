import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// ورقة الإجراءات السريعة — تُفتح من الزر الوسطي في الشريط السفلي.
///
/// لا تنفّذ شيئًا بنفسها: تستدعي الـcallbacks الممرّرة فقط (نفس سلوك السابق).
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.onDirectSale,
    required this.onPosAccounts,
    required this.onAddCustomer,
    this.onCreateCustomer,
    this.onOffers,
    this.onCards,
  });

  final VoidCallback onDirectSale;
  final VoidCallback onPosAccounts;
  final VoidCallback onAddCustomer;

  /// إنشاء حساب مشترك جديد (نموذج 1.0.9) — اختياري للتوافق الخلفي.
  final VoidCallback? onCreateCustomer;
  final VoidCallback? onOffers;
  final VoidCallback? onCards;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDirectSale,
    required VoidCallback onPosAccounts,
    required VoidCallback onAddCustomer,
    VoidCallback? onCreateCustomer,
    VoidCallback? onOffers,
    VoidCallback? onCards,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => QuickActionsSheet(
        onDirectSale: onDirectSale,
        onPosAccounts: onPosAccounts,
        onAddCustomer: onAddCustomer,
        onCreateCustomer: onCreateCustomer,
        onOffers: onOffers,
        onCards: onCards,
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
          NetSpacing.lg + bottom,
        ),
        // Scrollable so the six actions never overflow a short viewport.
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
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
            _ActionTile(
              icon: Icons.point_of_sale_outlined,
              label: 'البيع المباشر',
              onTap: () {
                Navigator.of(context).pop();
                onDirectSale();
              },
            ),
            _ActionTile(
              icon: Icons.storefront_outlined,
              label: 'حسابات نقاط البيع',
              onTap: () {
                Navigator.of(context).pop();
                onPosAccounts();
              },
            ),
            _ActionTile(
              icon: Icons.person_add_alt_1_outlined,
              label: 'إضافة عميل',
              onTap: () {
                Navigator.of(context).pop();
                onAddCustomer();
              },
            ),
            if (onCreateCustomer != null)
              _ActionTile(
                icon: Icons.person_add_alt_rounded,
                label: 'إنشاء حساب مشترك جديد',
                onTap: () {
                  Navigator.of(context).pop();
                  onCreateCustomer!();
                },
              ),
            if (onOffers != null)
              _ActionTile(
                icon: Icons.local_offer_outlined,
                label: 'العروض الترويجية',
                onTap: () {
                  Navigator.of(context).pop();
                  onOffers!();
                },
              ),
            if (onCards != null)
              _ActionTile(
                icon: Icons.style_outlined,
                label: 'مخزون الكروت',
                onTap: () {
                  Navigator.of(context).pop();
                  onCards!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.sm),
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: NetRadii.smAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: NetRadii.smAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: NetRadii.xsAll,
                  ),
                  child: Icon(icon, color: palette.primary),
                ),
                const SizedBox(width: NetSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_left_rounded, color: palette.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
