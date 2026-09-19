import 'package:flutter/material.dart';

import '../../theme/net_tokens.dart';
import '../async_views.dart';

/// Animates a minor-unit value from 0 to its target with an ease-out curve.
///
/// The rendered value is a plain [Text] so it stays testable and accessible.
/// The animation collapses to zero duration when the platform asks for
/// reduced motion.
class NetAnimatedCounter extends StatelessWidget {
  const NetAnimatedCounter({
    super.key,
    required this.valueMinor,
    this.style,
    this.duration = NetDurations.counter,
    this.animate = true,
    this.textAlign,
    this.maxLines = 1,
  });

  final int valueMinor;
  final TextStyle? style;
  final Duration duration;
  final bool animate;
  final TextAlign? textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final target = valueMinor / 100.0;
    final effective = animate ? NetMotion.scale(context, duration) : Duration.zero;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: effective,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(
        formatAmountOnly(value),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Small companion that renders the currency suffix (kept separate so the
/// number can use a bigger type size than the symbol).
class NetCurrencyLabel extends StatelessWidget {
  const NetCurrencyLabel({
    super.key,
    this.text = 'ر.ي',
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style ??
          TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
