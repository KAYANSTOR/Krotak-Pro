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
      secondaryContainer: Color(0xFFD1E8E8),
      tertiary: KayanColors.accentPink,
      tertiaryContainer: Color(0xFFFCE7F3),
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
    fontFamily: 'Tajawal',
  );

  return base.copyWith(
    scaffoldBackgroundColor: KayanColors.appBackground,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: KayanColors.appBackground,
      foregroundColor: KayanColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[NetSemanticColors.light],
  );
}

ThemeData buildNetDarkTheme() {
  final base = FlexThemeData.dark(
    colors: const FlexSchemeColor(
      primary: KayanColors.primary,
      primaryContainer: KayanColors.darkLightBackground,
      secondary: KayanColors.primaryVariant,
      secondaryContainer: Color(0xFF1E3A3A),
      tertiary: KayanColors.accentPink,
      tertiaryContainer: Color(0xFF4A1D36),
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
    fontFamily: 'Tajawal',
  );

  return base.copyWith(
    scaffoldBackgroundColor: KayanColors.darkAppBackground,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: KayanColors.darkAppBackground,
      foregroundColor: KayanColors.darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[NetSemanticColors.dark],
  );
}
