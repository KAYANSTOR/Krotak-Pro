import 'package:flutter/material.dart';

class NetQuickActionCard extends StatelessWidget {
  const NetQuickActionCard({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: cs.primary, size: 26),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ]),
        ),
      ),
    );
  }
}
