import 'package:flutter/material.dart';

/// Design tokens — لوحة كروتك الدافئة (تراكوطة / حجر دافئ).
/// مصدر واحد للألوان الأساسية في الوضعين الفاتح والغامق.
abstract final class KayanColors {
  // ── Light brand ──────────────────────────────────────────────
  static const primary = Color(0xFFD97757);
  static const primaryVariant = Color(0xFFB85C3E);
  static const lightBackground = Color(0xFFF3C5B5);
  static const accentPink = Color(0xFFC65D5D);
  static const appBackground = Color(0xFFF7F4EF);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF292524);
  static const textSecondary = Color(0xFF78716C);
  static const textTertiary = Color(0xFFA8A29E);
  static const border = Color(0xFFE7E2DC);
  static const borderGray = Color(0xFFE7E2DC);
  static const selectedBorder = Color(0xFFD97757);
  static const success = Color(0xFF6B8E72);
  static const successBackground = Color(0xFFE8F0E9);
  static const error = Color(0xFFC65D5D);
  static const errorBackground = Color(0xFFF8E8E8);
  static const errorBackgroundAlt = Color(0xFFFDF2F2);
  static const warning = Color(0xFFD59A3A);
  static const warningBackground = Color(0xFFFBF0E0);
  static const info = Color(0xFF64748B);
  static const infoBackground = Color(0xFFEEF1F4);
  static const logoGradient1 = Color(0xFFD97757);
  static const logoGradient2 = Color(0xFFB85C3E);
  static const logoGradient3 = Color(0xFFF3C5B5);

  // Premium accent — ذهب دافئ محدود الاستخدام (ترخيص / مكافآت)
  static const gold = Color(0xFFB8953A);
  static const goldContainer = Color(0xFFFDF6E3);
  static const darkGold = Color(0xFFE3C77A);
  static const darkGoldContainer = Color(0xFF43391A);

  // Brand gradient
  static const brandGradientStart = Color(0xFFD97757);
  static const brandGradientEnd = Color(0xFFB85C3E);
  static const darkBrandGradientStart = Color(0xFFE08A6A);
  static const darkBrandGradientEnd = Color(0xFFD97757);

  // ── Dark ─────────────────────────────────────────────────────
  static const darkAppBackground = Color(0xFF1F1F1F);
  static const darkSurface = Color(0xFF2A2A2A);
  static const darkSurfaceVariant = Color(0xFF333333);
  static const darkTextPrimary = Color(0xFFF5F0EB);
  static const darkTextSecondary = Color(0xFFA8A29E);
  static const darkBorder = Color(0xFF3F3F3F);
  static const darkLightBackground = Color(0xFF3D2A24);
}
