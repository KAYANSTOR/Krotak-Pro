import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';

/// نص البحث الحالي في لوحة الإعدادات.
///
/// يُوفّره لوحة الإعدادات لكل بطاقة مجموعة، فتُخفي الصفوف غير المطابقة
/// ويبقى البحث على مستوى الصف الواحد لا القسم فقط.
class SettingsSearchScope extends InheritedWidget {
  const SettingsSearchScope({
    super.key,
    required this.query,
    required super.child,
  });

  final String query;

  static String maybeQueryOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSearchScope>()?.query ??
      '';

  @override
  bool updateShouldNotify(SettingsSearchScope oldWidget) =>
      oldWidget.query != query;
}

/// صف قابل للبحث داخل بطاقة مجموعة.
abstract interface class SettingsSearchable {
  /// النص الذي يُطابَق عليه البحث: العنوان + الوصف + كلمات بديلة.
  String get searchableText;
}

/// بطاقة قسم مجمّعة — صفوف داخل حاوية واحدة مع فواصل (مطابق لإطارات الفيديو).
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 4),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final kayan = KayanPalette.of(context);
    final query = SettingsSearchScope.maybeQueryOf(context).trim().toLowerCase();
    final visible = <Widget>[];
    for (final child in children) {
      if (child is SettingsSearchable) {
        final matches = query.isEmpty ||
            child.searchableText.toLowerCase().contains(query);
        if (!matches) continue;
      }
      visible.add(child);
    }
    if (visible.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < visible.length; i++) {
      rows.add(visible[i]);
      if (i < visible.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 14,
          endIndent: 14,
          color: kayan.border,
        ));
      }
    }
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: kayan.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kayan.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// صف تنقّل داخل مجموعة: أيقونة يمين + عنوان/وصف + شيفرون.
class SettingsGroupNavRow extends StatelessWidget implements SettingsSearchable {
  const SettingsGroupNavRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.searchText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// مرادفات إضافية لا تظهر في الواجهة لكن يطابق عليها البحث.
  final String? searchText;

  @override
  String get searchableText => '$title ${subtitle ?? ''} ${searchText ?? ''}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, color: scheme.onSurfaceVariant, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// صف مفتاح داخل مجموعة: أيقونة + عنوان/وصف + Switch.
class SettingsGroupSwitchRow extends StatelessWidget
    implements SettingsSearchable {
  const SettingsGroupSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.searchText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  /// مرادفات إضافية لا تظهر في الواجهة لكن يطابق عليها البحث.
  final String? searchText;

  @override
  String get searchableText => '$title ${subtitle ?? ''} ${searchText ?? ''}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeTrackColor: KayanColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة منفصلة (للتوافق مع شاشات فرعية).
class SettingsCardShell extends StatelessWidget {
  const SettingsCardShell({
    super.key,
    required this.child,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final kayan = KayanPalette.of(context);
    final body = Material(
      color: kayan.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kayan.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: child,
        ),
      ),
    );
    return Padding(padding: margin, child: body);
  }
}

class SettingsNavCard extends StatelessWidget {
  const SettingsNavCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsCardShell(
      onTap: onTap,
      child: Row(
        children: [
          _IconBadge(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: TextStyle(
                fontFamily: 'Tajawal',
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isDark
            ? KayanColors.primary.withValues(alpha: 0.18)
            : const Color(0xFFE8F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: KayanColors.primary, size: 22),
    );
  }
}
