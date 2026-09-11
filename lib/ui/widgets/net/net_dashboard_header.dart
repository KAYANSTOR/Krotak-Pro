import 'package:flutter/material.dart';

class NetDashboardHeader extends StatelessWidget {
  const NetDashboardHeader({super.key, required this.title, this.subtitle, this.onSettings, this.onSearch, this.leading});
  final String title;
  final String? subtitle;
  final VoidCallback? onSettings;
  final VoidCallback? onSearch;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          if (leading != null) leading!,
          if (onSettings != null)
            IconButton(onPressed: onSettings, icon: Icon(Icons.settings_outlined, color: cs.onSurface), tooltip: 'الإعدادات'),
          Expanded(
            child: Column(
              children: [
                Text(title, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18, color: cs.onSurface)),
                if (subtitle != null)
                  Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (onSearch != null)
            IconButton(onPressed: onSearch, icon: Icon(Icons.search, color: cs.onSurface), tooltip: 'بحث')
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
