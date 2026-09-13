import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:net_app/ui/theme/theme_preference.dart';

void main() {
  group('ThemePreference', () {
    test('parses stored values', () {
      expect(ThemePreference.toThemeMode('dark'), ThemeMode.dark);
      expect(ThemePreference.toThemeMode('DARK'), ThemeMode.dark);
      expect(ThemePreference.toThemeMode('system'), ThemeMode.system);
      expect(ThemePreference.toThemeMode('light'), ThemeMode.light);
      expect(ThemePreference.toThemeMode(null), ThemeMode.light);
      expect(ThemePreference.toThemeMode('unknown'), ThemeMode.light);
    });

    test('round-trips ThemeMode', () {
      expect(ThemePreference.fromThemeMode(ThemeMode.dark), ThemePreference.dark);
      expect(ThemePreference.fromThemeMode(ThemeMode.light), ThemePreference.light);
      expect(ThemePreference.fromThemeMode(ThemeMode.system), ThemePreference.system);
    });

    test('normalizes unknown to light', () {
      expect(ThemePreference.normalize('  Dark '), ThemePreference.dark);
      expect(ThemePreference.normalize('foo'), ThemePreference.light);
    });
  });
}
