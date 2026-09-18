import 'package:flutter/material.dart';

import 'kayan_palette.dart';

/// Design tokens for the NET UI.
///
/// Single source of truth for spacing, radii, motion, elevation and the type
/// scale so screens never hardcode magic numbers again.
abstract final class NetSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Minimum tappable size (accessibility).
  static const double touchTarget = 48;

  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets screen = EdgeInsets.fromLTRB(lg, sm, lg, xxl);
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets cardTight = EdgeInsets.all(md);
  static const EdgeInsets row = EdgeInsets.symmetric(horizontal: md, vertical: md);

  /// Bottom inset so the last list item clears the bottom navigation bar.
  static const EdgeInsets listBottomInset = EdgeInsets.only(bottom: 88);
}

abstract final class NetRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double sheet = 28;
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const BorderRadius snack = BorderRadius.all(Radius.circular(sm));
}

abstract final class NetDurations {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration counter = Duration(milliseconds: 700);
}

abstract final class NetSizes {
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 28;
  static const double badge = 40;
  static const double avatar = 44;
  static const double logo = 36;
}

/// Motion helpers that honour the platform "reduce motion" accessibility flag.
abstract final class NetMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration scale(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Curves used across the app so every transition feels the same.
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
}

/// Elevated surfaces: two levels only (soft / raised), theme aware.
abstract final class NetElevation {
  static List<BoxShadow> soft(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.28 : 0.04),
        blurRadius: dark ? 10 : 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> raised(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.38 : 0.08),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ];
  }

  /// Coloured glow used behind gradient heroes (balance card, FAB sheets).
  static List<BoxShadow> glow(Color color, {double opacity = 0.28}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ];
}

/// The NET type scale. Widgets should read styles from here (or rely on the
/// ambient [TextTheme]) instead of building ad-hoc [TextStyle]s.
abstract final class NetTypography {
  static const String family = 'Tajawal';

  static TextTheme textTheme({required Color primary, required Color secondary}) {
    TextStyle base(double size, FontWeight weight, Color color) => TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.35,
        );

    return TextTheme(
      displaySmall: base(30, FontWeight.w800, primary),
      headlineMedium: base(24, FontWeight.w800, primary),
      headlineSmall: base(20, FontWeight.w800, primary),
      titleLarge: base(18, FontWeight.w800, primary),
      titleMedium: base(16, FontWeight.w700, primary),
      titleSmall: base(15, FontWeight.w700, primary),
      bodyLarge: base(15, FontWeight.w500, primary),
      bodyMedium: base(13.5, FontWeight.w500, primary),
      bodySmall: base(12, FontWeight.w500, secondary),
      labelLarge: base(14, FontWeight.w700, primary),
      labelMedium: base(12, FontWeight.w700, primary),
      labelSmall: base(11, FontWeight.w600, secondary),
    );
  }
}

/// Convenience accessor so widgets can grab tokens next to `context.kayan`.
extension NetTokensX on BuildContext {
  KayanPalette get palette => KayanPalette.of(this);
}
