import 'package:flutter/material.dart';

import 'kayan_colors.dart';

/// Semantic status colors for NET inventory, messaging, and finance UI.
@immutable
class NetSemanticColors extends ThemeExtension<NetSemanticColors> {
  const NetSemanticColors({
    required this.available,
    required this.availableContainer,
    required this.reserved,
    required this.reservedContainer,
    required this.sold,
    required this.soldContainer,
    required this.success,
    required this.successContainer,
    required this.error,
    required this.errorContainer,
    required this.warning,
    required this.warningContainer,
    required this.pending,
    required this.pendingContainer,
    required this.rejected,
    required this.rejectedContainer,
    required this.info,
    required this.infoContainer,
    required this.premium,
    required this.premiumContainer,
    required this.balanceGradientStart,
    required this.balanceGradientEnd,
    required this.alertBackground,
    required this.alertForeground,
  });

  final Color available;
  final Color availableContainer;
  final Color reserved;
  final Color reservedContainer;
  final Color sold;
  final Color soldContainer;
  final Color success;
  final Color successContainer;
  final Color error;
  final Color errorContainer;
  final Color warning;
  final Color warningContainer;
  final Color pending;
  final Color pendingContainer;
  final Color rejected;
  final Color rejectedContainer;
  final Color info;
  final Color infoContainer;

  /// لمسة ذهبية محدودة: الترخيص، المكافآت، وحالات الجاهزية الكاملة.
  final Color premium;
  final Color premiumContainer;
  final Color balanceGradientStart;
  final Color balanceGradientEnd;
  final Color alertBackground;
  final Color alertForeground;

  static const light = NetSemanticColors(
    available: KayanColors.success,
    availableContainer: KayanColors.successBackground,
    reserved: KayanColors.warning,
    reservedContainer: KayanColors.warningBackground,
    sold: KayanColors.primary,
    soldContainer: KayanColors.lightBackground,
    success: KayanColors.success,
    successContainer: KayanColors.successBackground,
    error: KayanColors.error,
    errorContainer: KayanColors.errorBackground,
    warning: KayanColors.warning,
    warningContainer: KayanColors.warningBackground,
    pending: KayanColors.info,
    pendingContainer: KayanColors.infoBackground,
    rejected: KayanColors.error,
    rejectedContainer: KayanColors.errorBackground,
    info: KayanColors.info,
    infoContainer: KayanColors.infoBackground,
    premium: KayanColors.gold,
    premiumContainer: KayanColors.goldContainer,
    balanceGradientStart: KayanColors.brandGradientStart,
    balanceGradientEnd: KayanColors.brandGradientEnd,
    alertBackground: KayanColors.warningBackground,
    alertForeground: Color(0xFF7C5A1A),
  );

  static const dark = NetSemanticColors(
    available: Color(0xFF8FB898),
    availableContainer: Color(0xFF1E2E22),
    reserved: Color(0xFFE0B060),
    reservedContainer: Color(0xFF3D2E12),
    sold: Color(0xFFE08A6A),
    soldContainer: Color(0xFF3D2A24),
    success: Color(0xFF8FB898),
    successContainer: Color(0xFF1E2E22),
    error: Color(0xFFE08080),
    errorContainer: Color(0xFF3D1F1F),
    warning: Color(0xFFE0B060),
    warningContainer: Color(0xFF3D2E12),
    pending: Color(0xFF94A3B8),
    pendingContainer: Color(0xFF1E2530),
    rejected: Color(0xFFE08080),
    rejectedContainer: Color(0xFF3D1F1F),
    info: Color(0xFF94A3B8),
    infoContainer: Color(0xFF1E2530),
    premium: KayanColors.darkGold,
    premiumContainer: KayanColors.darkGoldContainer,
    balanceGradientStart: KayanColors.darkBrandGradientStart,
    balanceGradientEnd: KayanColors.darkBrandGradientEnd,
    alertBackground: Color(0xFF3D2E12),
    alertForeground: Color(0xFFFBF0E0),
  );

  @override
  NetSemanticColors copyWith({
    Color? available,
    Color? availableContainer,
    Color? reserved,
    Color? reservedContainer,
    Color? sold,
    Color? soldContainer,
    Color? success,
    Color? successContainer,
    Color? error,
    Color? errorContainer,
    Color? warning,
    Color? warningContainer,
    Color? pending,
    Color? pendingContainer,
    Color? rejected,
    Color? rejectedContainer,
    Color? info,
    Color? infoContainer,
    Color? premium,
    Color? premiumContainer,
    Color? balanceGradientStart,
    Color? balanceGradientEnd,
    Color? alertBackground,
    Color? alertForeground,
  }) {
    return NetSemanticColors(
      available: available ?? this.available,
      availableContainer: availableContainer ?? this.availableContainer,
      reserved: reserved ?? this.reserved,
      reservedContainer: reservedContainer ?? this.reservedContainer,
      sold: sold ?? this.sold,
      soldContainer: soldContainer ?? this.soldContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      pending: pending ?? this.pending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      rejected: rejected ?? this.rejected,
      rejectedContainer: rejectedContainer ?? this.rejectedContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      premium: premium ?? this.premium,
      premiumContainer: premiumContainer ?? this.premiumContainer,
      balanceGradientStart: balanceGradientStart ?? this.balanceGradientStart,
      balanceGradientEnd: balanceGradientEnd ?? this.balanceGradientEnd,
      alertBackground: alertBackground ?? this.alertBackground,
      alertForeground: alertForeground ?? this.alertForeground,
    );
  }

  @override
  NetSemanticColors lerp(ThemeExtension<NetSemanticColors>? other, double t) {
    if (other is! NetSemanticColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NetSemanticColors(
      available: l(available, other.available),
      availableContainer: l(availableContainer, other.availableContainer),
      reserved: l(reserved, other.reserved),
      reservedContainer: l(reservedContainer, other.reservedContainer),
      sold: l(sold, other.sold),
      soldContainer: l(soldContainer, other.soldContainer),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      error: l(error, other.error),
      errorContainer: l(errorContainer, other.errorContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      pending: l(pending, other.pending),
      pendingContainer: l(pendingContainer, other.pendingContainer),
      rejected: l(rejected, other.rejected),
      rejectedContainer: l(rejectedContainer, other.rejectedContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      premium: l(premium, other.premium),
      premiumContainer: l(premiumContainer, other.premiumContainer),
      balanceGradientStart: l(balanceGradientStart, other.balanceGradientStart),
      balanceGradientEnd: l(balanceGradientEnd, other.balanceGradientEnd),
      alertBackground: l(alertBackground, other.alertBackground),
      alertForeground: l(alertForeground, other.alertForeground),
    );
  }
}

extension NetSemanticColorsX on BuildContext {
  NetSemanticColors get netColors =>
      Theme.of(this).extension<NetSemanticColors>() ?? NetSemanticColors.light;
}
