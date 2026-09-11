import 'package:flutter/material.dart';

class NetMetricCard extends StatelessWidget {
  const NetMetricCard({super.key, required this.title, required this.value, this.subtitle, this.icon, this.onTap});
  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: cs.primary), const SizedBox(width: 6)],
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: cs.onSurfaceVariant))),
            ]),
            const SizedBox(height: 8),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}
