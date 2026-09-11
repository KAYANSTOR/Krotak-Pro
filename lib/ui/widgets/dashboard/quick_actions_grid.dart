import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, this.onAction});

  final void Function(String action)? onAction;

  static const _actions = [
    (id: 'manualDirectSale', title: 'بيع مباشر - يدوي', icon: Icons.add),
    (id: 'salesPoints', title: 'حسابات نقاط البيع', icon: Icons.monitor),
    (id: 'blockedNumbers', title: 'الأرقام المحظورة', icon: Icons.shield_outlined),
    (id: 'importFiles', title: 'إدارة ملفات الاستيراد', icon: Icons.archive_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
        children: [
          for (final a in _actions)
            _QuickActionCard(
              title: a.title,
              icon: a.icon,
              onTap: () => onAction?.call(a.id),
            ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.icon,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KayanColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: KayanColors.borderGray),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: KayanColors.lightBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: KayanColors.primary, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: KayanColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
