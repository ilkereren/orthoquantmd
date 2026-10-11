import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'multi_image_template.dart';

/// Tibial tuberosity – trochlear groove distance (Dejour 1994), measured on
/// two axial slices of the same series. Both photos are straightened onto
/// the monitor by its corners, so they share one screen plane as long as the
/// viewer's zoom and pan stay unchanged.
class TtTgTemplate extends MultiImageTemplate {
  static const _img1Color = Color(0xFF4DD0E1);
  static const _img2Color = Color(0xFFFFB74D);
  static const _resultColor = Color(0xFFFFF176);

  @override
  String get id => 'tt_tg_distance';

  @override
  String get title => 'TT-TG Distance';

  @override
  String get viewInfo => 'Axial CT/MRI · 2 slices';

  @override
  IconData get icon => Icons.straighten;

  @override
  List<ImageStepSpec> get steps => const [
    ImageStepSpec(
      title: 'Trochlea',
      summary:
          'Most proximal slice with the complete cartilaginous trochlea. '
          'Calibrate, then mark both posterior condyles and the deepest '
          'point of the trochlear groove.',
      loadPrompt:
          'Photograph the monitor with all four corners visible, showing the '
          'most proximal axial CT/MRI slice with the complete cartilaginous '
          'trochlea.',
      landmarks: [
        LandmarkSpec(
          'mpc',
          'Medial PC',
          'Most posterior point of the medial femoral condyle',
        ),
        LandmarkSpec(
          'lpc',
          'Lateral PC',
          'Most posterior point of the lateral femoral condyle',
        ),
        LandmarkSpec('tg', 'TG', 'Deepest point of the trochlear groove'),
      ],
    ),
    ImageStepSpec(
      title: 'Tibial tuberosity',
      summary:
          'Most proximal slice where the patellar tendon inserts. Mark the '
          'midpoint of the insertion.',
      loadPrompt:
          'Scroll (do not pan or zoom) to the most proximal slice where the '
          'patellar tendon inserts on the tibial tuberosity, then photograph '
          'the monitor with all four corners visible.',
      landmarks: [
        LandmarkSpec('tt', 'TT', 'Midpoint of the patellar tendon insertion'),
      ],
      // Straightened onto the same screen plane as Image 1.
      calibrate: false,
    ),
  ];

  Offset _unit(Offset v) => v / v.distance;

  @override
  List<ResultLine> calculate(Map<String, Offset> mm) {
    final u = _unit(mm['lpc']! - mm['mpc']!); // medial → lateral
    final d =
        (mm['tt']! - mm['tg']!).dx * u.dx + (mm['tt']! - mm['tg']!).dy * u.dy;
    final abs = d.abs();
    final String grade;
    final Color color;
    if (abs < 15) {
      grade = 'Normal';
      color = Colors.greenAccent;
    } else if (abs <= 20) {
      grade = 'Borderline';
      color = Colors.orangeAccent;
    } else {
      grade = 'Pathological';
      color = Colors.redAccent;
    }
    return [
      ResultLine('TT-TG', '${abs.toStringAsFixed(1)} mm', color: color),
      // Side of TT relative to TG; grades: <15 normal, 15–20 borderline, >20 mm pathological.
      ResultLine('TT side', d >= 0 ? 'Lateral' : 'Medial'),
      ResultLine('Grade', grade, color: color),
    ];
  }

  void _extendedLine(Canvas c, Offset a, Offset b, Paint p, {double ext = 4}) {
    final d = b - a;
    c.drawLine(a - d * ext, b + d * ext, p);
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p, double s) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (double t = 0; t < len; t += 14 * s) {
      c.drawLine(a + dir * t, a + dir * math.min(t + 8 * s, len), p);
    }
  }

  void _point(Canvas c, Offset p, Color color, double s) {
    c.drawCircle(p, 5 * s, Paint()..color = color);
  }

  void _label(
    Canvas c,
    Offset p,
    String text,
    Color color,
    double s, {
    Offset shift = const Offset(8, -22),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 14 * s,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p + shift * s);
  }

  /// Perpendicular to the PCL through [p], spanning ±[half] px.
  (Offset, Offset) _perp(Offset p, Offset u, double half) {
    final n = Offset(-u.dy, u.dx);
    return (p - n * half, p + n * half);
  }

  @override
  void paintGhost(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double s,
  ) {
    final ghost = Paint()
      ..color = _img1Color.withValues(alpha: 0.85)
      ..strokeWidth = 1.5 * s
      ..style = PaintingStyle.stroke;
    if (mm.containsKey('mpc') && mm.containsKey('lpc')) {
      final a = toPx(mm['mpc']!), b = toPx(mm['lpc']!);
      _dashed(canvas, a - (b - a) * 2, b + (b - a) * 2, ghost, s);
      _label(canvas, b, 'PCL (Image 1)', _img1Color, s);
      if (mm.containsKey('tg')) {
        final tg = toPx(mm['tg']!);
        final (p1, p2) = _perp(tg, _unit(b - a), 2000);
        _dashed(canvas, p1, p2, ghost, s);
        _point(canvas, tg, _img1Color, s);
        _label(canvas, tg, 'TG (Image 1)', _img1Color, s);
      }
    }
    if (mm.containsKey('tt')) {
      final tt = toPx(mm['tt']!);
      _point(canvas, tt, _img2Color, s);
      _label(canvas, tt, 'TT (Image 2)', _img2Color, s);
    }
  }

  @override
  void paintCombined(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double s,
  ) {
    final mpc = toPx(mm['mpc']!), lpc = toPx(mm['lpc']!);
    final tg = toPx(mm['tg']!), tt = toPx(mm['tt']!);
    final u = _unit(lpc - mpc);

    final line1 = Paint()
      ..color = _img1Color
      ..strokeWidth = 2 * s;
    final line2 = Paint()
      ..color = _img2Color
      ..strokeWidth = 2 * s;

    _extendedLine(canvas, mpc, lpc, line1, ext: 1.5);
    final (a1, a2) = _perp(tg, u, 2000);
    _dashed(canvas, a1, a2, line1, s);
    final (b1, b2) = _perp(tt, u, 2000);
    _dashed(canvas, b1, b2, line2, s);

    // Dimension line at TT level, from TG's perpendicular to TT.
    final d = (tt - tg).dx * u.dx + (tt - tg).dy * u.dy;
    final foot = tt - u * d;
    final dim = Paint()
      ..color = _resultColor
      ..strokeWidth = 3 * s;
    canvas.drawLine(foot, tt, dim);
    for (final end in [foot, tt]) {
      final n = Offset(-u.dy, u.dx);
      canvas.drawLine(end - n * 8 * s, end + n * 8 * s, dim);
    }

    for (final (p, c, l) in [
      (mpc, _img1Color, 'Medial PC'),
      (lpc, _img1Color, 'Lateral PC'),
      (tg, _img1Color, 'TG'),
      (tt, _img2Color, 'TT'),
    ]) {
      _point(canvas, p, c, s);
      _label(canvas, p, l, c, s);
    }
    final mmPerUnit = calculate(mm).first.value;
    _label(
      canvas,
      (foot + tt) / 2,
      mmPerUnit,
      _resultColor,
      s,
      shift: const Offset(-30, 10),
    );
  }
}
