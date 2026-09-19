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
    available: Color(0xFF059669),
    availableContainer: Color(0xFFD1FAE5),
    reserved: Color(0xFFD97706),
    reservedContainer: Color(0xFFFEF3C7),
    sold: Color(0xFF6366F1),
    soldContainer: Color(0xFFE0E7FF),
    success: Color(0xFF059669),
    successContainer: Color(0xFFD1FAE5),
    error: Color(0xFFD93838),
    errorContainer: Color(0xFFFCE8E8),
    warning: Color(0xFFD97706),
    warningContainer: Color(0xFFFEF3C7),
    pending: Color(0xFF2563EB),
    pendingContainer: Color(0xFFDBEAFE),
    rejected: Color(0xFFB91C1C),
    rejectedContainer: Color(0xFFFEE2E2),
    info: KayanColors.info,
    infoContainer: KayanColors.infoBackground,
    premium: KayanColors.gold,
    premiumContainer: KayanColors.goldContainer,
    balanceGradientStart: KayanColors.brandGradientStart,
    balanceGradientEnd: KayanColors.brandGradientEnd,
    alertBackground: Color(0xFFFEF3C7),
    alertForeground: Color(0xFF92400E),
  );

  static const dark = NetSemanticColors(
    available: Color(0xFF34D399),
    availableContainer: Color(0xFF064E3B),
    reserved: Color(0xFFFBBF24),
    reservedContainer: Color(0xFF78350F),
    sold: Color(0xFFA5B4FC),
    soldContainer: Color(0xFF312E81),
    success: Color(0xFF34D399),
    successContainer: Color(0xFF064E3B),
    error: Color(0xFFF87171),
    errorContainer: Color(0xFF7F1D1D),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF78350F),
    pending: Color(0xFF60A5FA),
    pendingContainer: Color(0xFF1E3A8A),
    rejected: Color(0xFFF87171),
    rejectedContainer: Color(0xFF7F1D1D),
    info: Color(0xFF93C5FD),
    infoContainer: Color(0xFF1E3A8A),
    premium: KayanColors.darkGold,
    premiumContainer: KayanColors.darkGoldContainer,
    balanceGradientStart: KayanColors.darkBrandGradientStart,
    balanceGradientEnd: KayanColors.darkBrandGradientEnd,
    alertBackground: Color(0xFF78350F),
    alertForeground: Color(0xFFFEF3C7),
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
