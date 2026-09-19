import 'package:flutter/material.dart';

import '../../theme/net_tokens.dart';

/// Minimal, dependency-free sparkline used by the dashboard KPI cards.
///
/// Values are drawn oldest → newest; the order is mirrored in RTL so the chart
/// reads in the same direction as the Arabic layout.
class NetSparkline extends StatelessWidget {
  const NetSparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 32,
    this.showArea = true,
    this.strokeWidth = 2,
  });

  final List<double> values;
  final Color? color;
  final double height;
  final bool showArea;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final series = rtl ? values.reversed.toList(growable: false) : values;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: series,
          color: tint,
          showArea: showArea,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.showArea,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final bool showArea;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final series = values.isEmpty ? const <double>[0, 0] : values;
    var min = series.first;
    var max = series.first;
    for (final v in series) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = (max - min).abs() < 0.0001 ? 1.0 : (max - min);

    final stepX = series.length > 1 ? size.width / (series.length - 1) : size.width;
    double yFor(double v) {
      final normalized = (v - min) / range;
      // Leave one stroke width of headroom so the line never clips.
      final usable = (size.height - strokeWidth).clamp(1.0, size.height);
      return size.height - normalized * usable - strokeWidth / 2;
    }

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final x = stepX * i;
      final y = yFor(series[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (showArea) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size);
      canvas.drawPath(area, fill);
    }

    canvas.drawPath(path, stroke);

    // Endpoint dot marks the latest value.
    if (series.length > 1) {
      final last = Offset(stepX * (series.length - 1), yFor(series.last));
      canvas.drawCircle(last, strokeWidth + 0.8, Paint()..color = color);
      canvas.drawCircle(
        last,
        strokeWidth + 0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Horizontal segmented ratio bar (available / reserved / sold).
class NetRatioBar extends StatelessWidget {
  const NetRatioBar({
    super.key,
    required this.segments,
    this.height = 8,
    this.radius = NetRadii.pill,
  });

  /// Ordered segments: (value, color). Zero values are skipped.
  final List<({int value, Color color})> segments;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, s) => sum + (s.value > 0 ? s.value : 0));
    final visible = segments.where((s) => s.value > 0).toList(growable: false);

    Widget bar;
    if (total <= 0 || visible.isEmpty) {
      bar = Container(
        color: Theme.of(context).colorScheme.outlineVariant,
        height: height,
      );
    } else {
      bar = Row(
        children: [
          for (final segment in visible)
            Expanded(
              flex: segment.value,
              child: Container(color: segment.color, height: height),
            ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(height: height, child: bar),
    );
  }
}
