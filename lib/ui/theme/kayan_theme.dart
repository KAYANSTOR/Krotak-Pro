import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kayan_colors.dart';

ThemeData buildKayanLightTheme() {
  final colorScheme = ColorScheme.light(
    primary: KayanColors.primary,
    onPrimary: Colors.white,
    secondary: KayanColors.primaryVariant,
    onSecondary: Colors.white,
    tertiary: KayanColors.accentPink,
    onTertiary: Colors.white,
    surface: KayanColors.surface,
    onSurface: KayanColors.textPrimary,
    error: KayanColors.error,
    onError: Colors.white,
    errorContainer: KayanColors.errorBackground,
    onErrorContainer: KayanColors.error,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Tajawal',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: KayanColors.appBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: KayanColors.appBackground,
      foregroundColor: KayanColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: KayanColors.appBackground,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: KayanColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: KayanColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KayanColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: KayanColors.surface,
      indicatorColor: KayanColors.lightBackground,
    ),
  );
}

ThemeData buildKayanDarkTheme() {
  final colorScheme = ColorScheme.dark(
    primary: KayanColors.primary,
    onPrimary: Colors.white,
    secondary: KayanColors.primaryVariant,
    onSecondary: Colors.white,
    tertiary: KayanColors.accentPink,
    onTertiary: Colors.white,
    surface: KayanColors.darkSurface,
    onSurface: KayanColors.darkTextPrimary,
    error: KayanColors.error,
    onError: Colors.white,
    outline: KayanColors.darkBorder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Tajawal',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: KayanColors.darkAppBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: KayanColors.darkAppBackground,
      foregroundColor: KayanColors.darkTextPrimary,
      elevation: 0,
      centerTitle: true,
    ),
  );
}
