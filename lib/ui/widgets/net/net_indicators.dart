import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Small KPI indicator used by summaries (accounts, stock, reports).
///
/// One design language for "indicators": tinted icon badge, label, value.
class NetIndicatorTile extends StatelessWidget {
  const NetIndicatorTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tint,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tint;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final color = tint ?? palette.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: palette.isDark ? 0.22 : 0.10),
            borderRadius: NetRadii.smAll,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: NetSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 10.5,
                    color: palette.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lays [indicators] out in a fixed-column grid inside an existing card.
class NetIndicatorGrid extends StatelessWidget {
  const NetIndicatorGrid({
    super.key,
    required this.indicators,
    this.columns = 2,
    this.spacing = NetSpacing.md,
  });

  final List<NetIndicatorTile> indicators;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < indicators.length; i += columns) {
      final slice = indicators.sublist(
        i,
        (i + columns) > indicators.length ? indicators.length : i + columns,
      );
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) SizedBox(width: spacing),
              Expanded(
                child: j < slice.length
                    ? slice[j]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// A single horizontal bar row: label (start) · bar · value (end).
class NetBarRow extends StatelessWidget {
  const NetBarRow({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    this.valueLabel,
    this.trailing,
    this.labelWidth = 96,
    this.barHeight = 9,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final String? valueLabel;
  final Widget? trailing;
  final double labelWidth;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final factor = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NetSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: NetRadii.pillAll,
              child: SizedBox(
                height: barHeight,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: palette.surfaceVariant),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: factor,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: color),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: NetSpacing.sm),
          if (trailing != null) trailing!,
          if (valueLabel != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                valueLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One datum of a [NetHorizontalBars] chart.
@immutable
class NetBarDatum {
  const NetBarDatum({
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
  });

  final String label;
  final double value;
  final Color color;
  final String? valueLabel;
}

/// Horizontal bar chart (Arabic RTL friendly) used by KPI summaries.
class NetHorizontalBars extends StatelessWidget {
  const NetHorizontalBars({
    super.key,
    required this.data,
    this.barHeight = 9,
    this.labelWidth = 96,
    this.emptyMessage = 'لا توجد بيانات لعرضها',
  });

  final List<NetBarDatum> data;
  final double barHeight;
  final double labelWidth;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NetSpacing.sm),
        child: Text(
          emptyMessage,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12.5,
            color: palette.textTertiary,
          ),
        ),
      );
    }

    final maxValue = data
        .map((e) => e.value.abs())
        .fold<double>(0, (a, b) => b > a ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < data.length; i++) ...[
          NetBarRow(
            label: data[i].label,
            value: data[i].value.abs(),
            maxValue: maxValue,
            color: data[i].color,
            valueLabel: data[i].valueLabel,
            barHeight: barHeight,
            labelWidth: labelWidth,
          ),
          if (i < data.length - 1) Divider(height: 1, color: palette.border),
        ],
      ],
    );
  }
}
