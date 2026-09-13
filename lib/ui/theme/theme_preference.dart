import 'package:flutter/material.dart';

/// Persisted theme preference: system / light / dark.
abstract final class ThemePreference {
  static const system = 'system';
  static const light = 'light';
  static const dark = 'dark';

  static const values = [system, light, dark];

  static ThemeMode toThemeMode(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case dark:
        return ThemeMode.dark;
      case system:
        return ThemeMode.system;
      case light:
      default:
        return ThemeMode.light;
    }
  }

  static String fromThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return dark;
      case ThemeMode.system:
        return system;
      case ThemeMode.light:
        return light;
    }
  }

  static String normalize(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == dark || v == system || v == light) return v;
    return light;
  }

  static String labelAr(String value) {
    switch (normalize(value)) {
      case dark:
        return 'داكن';
      case system:
        return 'حسب الجهاز';
      case light:
      default:
        return 'فاتح';
    }
  }
}
