import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';

/// Dashboard FAB sheet — master-plan quick actions.
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({
    super.key,
    required this.onDirectSale,
    required this.onPosAccounts,
    required this.onAddCustomer,
  });

  final VoidCallback onDirectSale;
  final VoidCallback onPosAccounts;
  final VoidCallback onAddCustomer;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDirectSale,
    required VoidCallback onPosAccounts,
    required VoidCallback onAddCustomer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickActionsSheet(
        onDirectSale: onDirectSale,
        onPosAccounts: onPosAccounts,
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
            ),
            Text(
              'إجراءات سريعة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.iconBadgeBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: KayanColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_left, color: palette.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
