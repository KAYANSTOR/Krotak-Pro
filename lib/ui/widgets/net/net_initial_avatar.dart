import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Deterministic letter avatar: the same account always gets the same hue, so
/// long lists stay scannable without shipping any image assets.
class NetInitialAvatar extends StatelessWidget {
  const NetInitialAvatar({
    super.key,
    required this.name,
    this.size = NetSizes.avatar,
    this.isPrimary = false,
  });

  final String name;
  final double size;
  final bool isPrimary;

  static const List<Color> _palette = <Color>[
    Color(0xFF247A7B),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0EA5E9),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF6366F1),
    Color(0xFFDC2626),
  ];

  static Color colorFor(String seed) {
    if (seed.isEmpty) return _palette.first;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  static String initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '؟';
    return String.fromCharCode(trimmed.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final tint = colorFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: palette.isDark ? 0.26 : 0.14),
        shape: BoxShape.circle,
        border: Border.all(
          color: tint.withValues(alpha: palette.isDark ? 0.45 : 0.22),
        ),
      ),
      child: Text(
        initialFor(name),
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: palette.isDark ? tint.withValues(alpha: 0.95) : tint,
        ),
      ),
    );
  }
}

/// Semantic balance pill used by the accounts list (debtor / creditor / clear).
class NetBalancePill extends StatelessWidget {
  const NetBalancePill({
    super.key,
    required this.amountMinor,
    this.currency = 'ر.ي',
    this.compact = false,
  });

  final int amountMinor;
  final String currency;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final isZero = amountMinor == 0;
    final isDebt = amountMinor < 0;
    final tint = isZero
        ? palette.textSecondary
        : isDebt
            ? Theme.of(context).colorScheme.error
            : const Color(0xFF059669);

    final major = amountMinor.abs() / 100.0;
    final text = major == major.roundToDouble()
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
    final prefix = isZero ? '' : (isDebt ? '-' : '+');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? NetSpacing.sm : NetSpacing.md,
        vertical: NetSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: palette.isDark ? 0.20 : 0.10),
        borderRadius: NetRadii.pillAll,
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Text(
        isZero ? 'لا رصيد' : '$prefix$text $currency',
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: compact ? 11.5 : 12.5,
          fontWeight: FontWeight.w800,
          color: tint,
        ),
      ),
    );
  }
}
