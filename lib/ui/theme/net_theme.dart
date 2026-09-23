import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kayan_colors.dart';
import 'kayan_palette.dart';
import 'net_semantic_colors.dart';
import 'net_tokens.dart';

/// NET theme built on FlexColorScheme, extended with the full set of component
/// themes so screens inherit radii, borders and typography instead of
/// hardcoding colors and magic numbers.
ThemeData buildNetLightTheme() => _buildNetTheme(isDark: false);

ThemeData buildNetDarkTheme() => _buildNetTheme(isDark: true);

ThemeData _buildNetTheme({required bool isDark}) {
  final palette = isDark ? KayanPalette.dark : KayanPalette.light;
  final semantic = isDark ? NetSemanticColors.dark : NetSemanticColors.light;

  final base = isDark
      ? FlexThemeData.dark(
          colors: const FlexSchemeColor(
            primary: KayanColors.primary,
            primaryContainer: KayanColors.darkLightBackground,
            secondary: KayanColors.primaryVariant,
            secondaryContainer: Color(0xFF3D2A24),
            tertiary: KayanColors.accentPink,
            tertiaryContainer: Color(0xFF4A2A2A),
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
          fontFamily: NetTypography.family,
        )
      : FlexThemeData.light(
          colors: const FlexSchemeColor(
            primary: KayanColors.primary,
            primaryContainer: KayanColors.lightBackground,
            secondary: KayanColors.primaryVariant,
            secondaryContainer: Color(0xFFF3C5B5),
            tertiary: KayanColors.accentPink,
            tertiaryContainer: Color(0xFFF8E8E8),
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
          fontFamily: NetTypography.family,
        );

  final textTheme = NetTypography.textTheme(
    primary: palette.textPrimary,
    secondary: palette.textSecondary,
  ).apply(fontFamily: NetTypography.family);

  final scheme = base.colorScheme.copyWith(
    onSurface: palette.textPrimary,
    onSurfaceVariant: palette.textSecondary,
    surface: palette.surface,
    outlineVariant: palette.border,
    outline: isDark ? KayanColors.darkSurfaceVariant : KayanColors.borderGray,
  );

  final pillShape = RoundedRectangleBorder(borderRadius: NetRadii.smAll);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.appBackground,
    canvasColor: palette.appBackground,
    cardColor: palette.surface,
    dividerColor: palette.border,
    textTheme: textTheme,
    primaryTextTheme: textTheme,

    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: palette.appBackground,
      foregroundColor: palette.textPrimary,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
      iconTheme: IconThemeData(color: palette.textPrimary, size: NetSizes.iconMd),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    ),

    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: NetRadii.mdAll,
        side: BorderSide(color: palette.border),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.surface,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: NetRadii.sheetTop),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: NetRadii.lgAll),
      titleTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: palette.textPrimary,
      ),
      contentTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 14,
        height: 1.5,
        color: palette.textSecondary,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? KayanColors.darkSurfaceVariant : KayanColors.textPrimary,
      contentTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: isDark ? KayanColors.darkTextPrimary : Colors.white,
      ),
      actionTextColor: isDark ? KayanColors.primary : KayanColors.lightBackground,
      elevation: 2,
      insetPadding: NetSpacing.pageH,
      shape: const RoundedRectangleBorder(borderRadius: NetRadii.snack),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(NetSpacing.touchTarget, NetSpacing.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: NetSpacing.xl),
        shape: pillShape,
        textStyle: const TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(NetSpacing.touchTarget, NetSpacing.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: NetSpacing.xl),
        side: BorderSide(color: palette.border),
        foregroundColor: KayanColors.primary,
        shape: pillShape,
        textStyle: const TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(NetSpacing.touchTarget, 40),
        padding: const EdgeInsets.symmetric(horizontal: NetSpacing.md),
        foregroundColor: KayanColors.primary,
        shape: pillShape,
        textStyle: const TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceVariant,
      selectedColor: KayanColors.primary,
      secondarySelectedColor: KayanColors.primary,
      disabledColor: palette.surfaceVariant,
      side: BorderSide(color: palette.border),
      shape: RoundedRectangleBorder(borderRadius: NetRadii.pillAll),
      padding: const EdgeInsets.symmetric(horizontal: NetSpacing.sm, vertical: NetSpacing.xs),
      labelStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      brightness: isDark ? Brightness.dark : Brightness.light,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: palette.surfaceVariant,
      circularTrackColor: Colors.transparent,
    ),

    listTileTheme: ListTileThemeData(
      textColor: palette.textPrimary,
      iconColor: KayanColors.primary,
      subtitleTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        color: palette.textSecondary,
        fontSize: 13,
      ),
      titleTextStyle: TextStyle(
        fontFamily: NetTypography.family,
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    ),

    extensions: <ThemeExtension<dynamic>>[semantic],
  );
}
