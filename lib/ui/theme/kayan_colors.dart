import 'package:flutter/material.dart';

/// Design tokens extracted from kayan-android-kotlan
/// (app/src/main/java/com/example/core/theme/Color.kt)
abstract final class KayanColors {
  // Light
  static const primary = Color(0xFF247A7B);
  static const primaryVariant = Color(0xFF1E6667);
  static const lightBackground = Color(0xFFE6F4F1);
  static const accentPink = Color(0xFFDB2777);
  static const appBackground = Color(0xFFF6F8F9);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1A202C);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const border = Color(0xFFE2E8F0);
  static const borderGray = Color(0xFFE5E7EB);
  static const selectedBorder = Color(0xFF247A7B);
  static const success = Color(0xFF059669);
  static const successBackground = Color(0xFFD1FAE5);
  static const error = Color(0xFFD93838);
  static const errorBackground = Color(0xFFFCE8E8);
  static const errorBackgroundAlt = Color(0xFFFEF2F2);
  static const warning = Color(0xFFD97706);
  static const warningBackground = Color(0xFFFEF3C7);
  static const info = Color(0xFF1D4ED8);
  static const infoBackground = Color(0xFFEFF6FF);
  static const logoGradient1 = Color(0xFF247A7B);
  static const logoGradient2 = Color(0xFF7B61FF);
  static const logoGradient3 = Color(0xFFE04096);

  // Brand gradient — one definition for every hero surface in the app.
  static const brandGradientStart = Color(0xFF247A7B);
  static const brandGradientEnd = Color(0xFFA4508B);
  static const darkBrandGradientStart = Color(0xFF1E6667);
  static const darkBrandGradientEnd = Color(0xFF7B3F6A);

  // Dark
  static const darkAppBackground = Color(0xFF0F1117);
  static const darkSurface = Color(0xFF1A1D27);
  static const darkSurfaceVariant = Color(0xFF252836);
  static const darkTextPrimary = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkBorder = Color(0xFF2D3142);
  static const darkLightBackground = Color(0xFF1E3A3A);
}
