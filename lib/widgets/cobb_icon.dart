import 'package:flutter/material.dart';

/// Stylised "Cobb angle" icon used by the measurement tool menu.
///
/// Renders three small vertebrae stacked at slight angles plus the two
/// reference lines whose intersection forms a Cobb angle.
class CobbIcon extends StatelessWidget {
  final Color color;
  const CobbIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: CobbPainter(color),
    );
  }
}

class CobbPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  CobbPainter(this.color, {this.strokeWidth = 2.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Vertebrae (Rounded Rects)
    // Top
    _drawRotatedRect(canvas, paint, cx + 2, cy - 8, -15 * 3.14159 / 180);
    // Mid
    _drawRotatedRect(canvas, paint, cx - 2, cy, 0);
    // Bot
    _drawRotatedRect(canvas, paint, cx + 2, cy + 8, 15 * 3.14159 / 180);

    // Lines (Abstract intersection)
    // Top Line (extending from top vert)
    canvas.drawLine(Offset(cx - 8, cy - 10), Offset(cx + 8, cy - 14), paint..strokeWidth = 1.5);
    // Bot Line (extending from bot vert)
    canvas.drawLine(Offset(cx - 8, cy + 10), Offset(cx + 8, cy + 14), paint);
  }

  void _drawRotatedRect(Canvas canvas, Paint paint, double x, double y, double angle) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 6),
        const Radius.circular(2),
      ),
      paint..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
