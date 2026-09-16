import 'package:flutter/material.dart';

import '../../theme/kayan_colors.dart';

/// بطاقة قسم مجمّعة — صفوف داخل حاوية بيضاء واحدة مع فواصل (مطابق لإطارات الفيديو).
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
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Divider(
          height: 1,
          thickness: 1,
          indent: 14,
          endIndent: 14,
          color: KayanColors.borderGray,
        ));
      }
    }
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: KayanColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KayanColors.borderGray),
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

/// صف تنقّل داخل مجموعة: أيقونة يمين + عنوان/وصف + شيفرون يسار.
class SettingsGroupNavRow extends StatelessWidget {
  const SettingsGroupNavRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KayanColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          height: 1.35,
                          color: KayanColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left, color: KayanColors.textTertiary, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// صف مفتاح داخل مجموعة: أيقونة يمين + عنوان/وصف + Switch يسار.
class SettingsGroupSwitchRow extends StatelessWidget {
  const SettingsGroupSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
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
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: KayanColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          height: 1.35,
                          color: KayanColors.textSecondary,
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
    final body = Material(
      color: KayanColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: KayanColors.borderGray),
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
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KayanColors.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: KayanColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                value!,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KayanColors.primary,
                ),
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left, color: KayanColors.textTertiary),
          ],
        ],
      ),
    );
  }
}

class SettingsSwitchCard extends StatelessWidget {
  const SettingsSwitchCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsCardShell(
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
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
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KayanColors.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: KayanColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: KayanColors.primary,
          ),
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
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: KayanColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: KayanColors.primary, size: 22),
    );
  }
}
