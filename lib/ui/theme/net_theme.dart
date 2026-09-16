import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kayan_colors.dart';
import 'net_semantic_colors.dart';

ThemeData buildNetLightTheme() {
  final base = FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: KayanColors.primary,
      primaryContainer: KayanColors.lightBackground,
      secondary: KayanColors.primaryVariant,
      secondaryContainer: Color(0xD1E8E8),
      tertiary: KayanColors.accentPink,
      tertiaryContainer: Color(0xFCE7F3),
      appBarColor: KayanColors.appBackground,
      error: KayanColors.error,
    ),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 6,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 8,
      useM2StyleDividerInM3: true,
      inputDecoratorRadius: 12,
      cardRadius: 16,
      elevatedButtonRadius: 12,
      filledButtonRadius: 12,
      outlinedButtonRadius: 12,
      navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
      navigationBarIndicatorSchemeColor: SchemeColor.primaryContainer,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    fontFamily: 'Roboto',
  );

  final textTheme = base.textTheme.apply(
    bodyColor: KayanColors.textPrimary,
    displayColor: KayanColors.textPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: KayanColors.appBackground,
    canvasColor: KayanColors.appBackground,
    cardColor: KayanColors.surface,
    dividerColor: KayanColors.border,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    listTileTheme: const ListTileThemeData(
      textColor: KayanColors.textPrimary,
      iconColor: KayanColors.primary,
      subtitleTextStyle: TextStyle(
        color: KayanColors.textSecondary,
        fontSize: 13,
      ),
      titleTextStyle: TextStyle(
        color: KayanColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: KayanColors.appBackground,
      foregroundColor: KayanColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        color: KayanColors.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark.
      ),
    ),
    colorScheme: base.colorScheme.copyWith(
      onSurface: KayanColors.textPrimary,
      onSurfaceVariant: KayanColors.textSecondary,
      surface: KayanColors.surface,
    ),
    extensions: <ThemeExtension<dynamic>>[NetSemanticColors.light],
  );
}

ThemeData buildNetDarkTheme() {
  final base = FlexThemeData.dark(
    colors: const FlexSchemeColor(J
      primary: KayanColors.primary,
      primaryContainer: KayanColors.darkLightBackground,
      secondary: KayanColors.primaryVariant,
      secondaryContainer: Color(0x1E3A3A),
      tertiary: KayanColors.accentPink,
      tertiaryContainer: Color(0x4A1D36),
      appBarColor: KayanColors.darkAppBackground,
      error: KayanColors.error,
    ),
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 10,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 12,
      useM2StyleDividerInM3: true,
      inputDecoratorRadius: 12,
      cardRadius: 16,
      elevatedButtonRadius: 12,
      filledButtonRadius: 12,
      outlinedButtonRadius: 12,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    fontFamily: 'Roboto',
  );

  final textTheme = base.textTheme.apply(
    bodyColor: KayanColors.darkTextPrimary,
    displayColor: KayanColors.darkTextPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: KayanColors.darkAppBackground,
    canvasColor: KayanColors.darkAppBackground,
    cardColor: KayanColors.darkSurface,
    dividerColor: KayanColors.darkBorder,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    listTileTheme: const ListTileThemeData(
      textColor: KayanColors.darkTextPrimary,
      iconColor: KayanColors.primary,
      subtitleTextStyle: TextStyle(
        color: KayanColors.darkTextSecondary,
        fontSize: 13,
      ),
      titleTextStyle: TextStyle(
        color: KayanColors.darkTextPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: KayanColors.darkAppBackground,
      foregroundColor: KayanColors.darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        color: KayanColors.darkTextPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    colorScheme: base.colorScheme.copyWith(
      onSurface: KayanColors.darkTextPrimary,
      onSurfaceVariant: KayanColors.darkTextSecondary,
      surface: KayanColors.darkSurface,
    ),
    extensions: <ThemeExtension<dynamic>[NetSemanticColors.dark],
  );
}
