import 'package:flutter/material.dart';

import 'kayan_colors.dart';

/// Adaptive chrome colors that follow the active brightness.
/// Use this instead of raw [KayanColors] light tokens in widgets.
@immutable
class KayanPalette {
  const KayanPalette({
    required this.isDark,
    required this.appBackground,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.iconBadgeBackground,
    required this.disabledForeground,
  });

  final bool isDark;
  final Color appBackground;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color iconBadgeBackground;
  final Color disabledForeground;

  static const light = KayanPalette(
    isDark: false,
    appBackground: KayanColors.appBackground,
    surface: KayanColors.surface,
    surfaceVariant: KayanColors.lightBackground,
    textPrimary: KayanColors.textPrimary,
    textSecondary: KayanColors.textSecondary,
    textTertiary: KayanColors.textTertiary,
    border: KayanColors.borderGray,
    iconBadgeBackground: KayanColors.lightBackground,
    disabledForeground: Color(0xFF9CA3AF),
  );

  static const dark = KayanPalette(
    isDark: true,
    appBackground: KayanColors.darkAppBackground,
    surface: KayanColors.darkSurface,
    surfaceVariant: KayanColors.darkSurfaceVariant,
    textPrimary: KayanColors.darkTextPrimary,
    textSecondary: KayanColors.darkTextSecondary,
    textTertiary: Color(0xFF64748B),
    border: KayanColors.darkBorder,
    iconBadgeBackground: KayanColors.darkLightBackground,
    disabledForeground: Color(0xFF64748B),
  );

  static KayanPalette of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}

extension KayanPaletteX on BuildContext {
  KayanPalette get kayan => KayanPalette.of(this);
}

/// Maps persisted theme_mode values to [ThemeMode].
abstract final class ThemeModeCodec {
  static ThemeMode parse(String? raw) {
    switch ((raw ?? SettingThemeValues.light).trim().toLowerCase()) {
      case SettingThemeValues.dark:
        return ThemeMode.dark;
      case SettingThemeValues.system:
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  static String encode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.dark => SettingThemeValues.dark,
      ThemeMode.system => SettingThemeValues.system,
      ThemeMode.light => SettingThemeValues.light,
    };
  }
}

abstract final class SettingThemeValues {
  static const light = 'light';
  static const dark = 'dark';
  static const system = 'system';
}
