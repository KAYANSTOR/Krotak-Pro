import 'package:flutter/material.dart';

/// Brand mark for NET Dashboard Header (no external asset required).
class NetAppLogo extends StatelessWidget {
  const NetAppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(size * 0.7, size * 0.7),
        painter: _NetLogoPainter(
          colors: [
            cs.primary,
            cs.tertiary,
            cs.secondary,
          ],
        ),
      ),
    );
  }
}

class _NetLogoPainter extends CustomPainter {
  _NetLogoPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = Paint()
      ..shader = LinearGradient(
        colors: colors.length >= 2 ? colors : [colors.first, colors.first],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final top = Path()
      ..moveTo(w * 0.25, h * 0.40)
      ..cubicTo(w * 0.40, h * 0.20, w * 0.60, h * 0.20, w * 0.75, h * 0.40);
    canvas.drawPath(top, gradient);

    final mid = Path()
      ..moveTo(w * 0.35, h * 0.53)
      ..cubicTo(w * 0.45, h * 0.43, w * 0.55, h * 0.43, w * 0.65, h * 0.53);
    canvas.drawPath(mid, gradient);

    final bottom = Path()
      ..moveTo(w * 0.45, h * 0.66)
      ..cubicTo(w * 0.50, h * 0.60, w * 0.55, h * 0.60, w * 0.60, h * 0.66)
      ..lineTo(w * 0.45, h * 0.82)
      ..cubicTo(w * 0.55, h * 0.82, w * 0.60, h * 0.75, w * 0.62, h * 0.70);
    canvas.drawPath(bottom, gradient);
  }

  @override
  bool shouldRepaint(covariant _NetLogoPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
