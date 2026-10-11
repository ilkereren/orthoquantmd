import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'multi_image_template.dart';

/// Femoral version by the Reikerås method, on three axial CT slices of the
/// same series: the femoral head centre (a ring fitted to the head) and the
/// neck centre on their own slices give the neck axis, compared with the
/// posterior condylar line on a distal slice.
///
/// The neck axis joins points from two photos, so a shift between them
/// would turn the axis: the photos are straightened onto the monitor by its
/// corners like every multi-image template. Angle only, so no calibration.
///
/// Images are read in the standard axial orientation (anterior at the top).
/// Positive = anteversion (head anterior to the neck), negative =
/// retroversion; the side (left/right) does not matter.
class FemoralVersionTemplate extends MultiImageTemplate {
  static const _img1Color = Color(0xFF4DD0E1);
  static const _img2Color = Color(0xFFFFB74D);
  static const _resultColor = Color(0xFFFFF176);

  @override
  String get id => 'femoral_version_reikeras';

  @override
  String get title => 'Femoral Version';

  @override
  String get viewInfo => 'Axial CT · Reikerås · 3 slices';

  @override
  IconData get icon => Icons.rotate_right;

  @override
  List<ImageStepSpec> get steps => const [
    ImageStepSpec(
      title: 'Femoral head',
      summary:
          'Slice through the centre of the femoral head. Tap the head; a '
          'ring appears. Fit the ring to the head\'s outline: its centre is '
          'the head centre.',
      loadPrompt:
          'Photograph the monitor with all four corners visible, showing the '
          'axial slice through the centre of the femoral head (anterior at '
          'the top).',
      landmarks: [
        LandmarkSpec(
          'head',
          'Head',
          'Tap the femoral head, then fit the ring to its outline',
          ring: true,
        ),
      ],
      calibrate: false,
    ),
    ImageStepSpec(
      title: 'Femoral neck',
      // Reikerås: the neck level where the cortices run parallel. A point
      // at the neck base would make it Murphy's method, with higher values.
      summary:
          'Slice through the femoral neck where its anterior and posterior '
          'cortices run parallel. Mark the midpoint between the two '
          'cortices.',
      loadPrompt:
          'Scroll (do not pan or zoom) to the femoral neck slice where its '
          'anterior and posterior cortices run parallel, then photograph the '
          'monitor with all four corners visible.',
      landmarks: [
        LandmarkSpec(
          'neck',
          'Neck centre',
          'Midpoint between the anterior and posterior cortices of the neck',
        ),
      ],
      calibrate: false,
    ),
    ImageStepSpec(
      title: 'Femoral condyles',
      summary:
          'Distal femur slice. Mark the most posterior points of both '
          'condyles.',
      loadPrompt:
          'Scroll (do not pan or zoom) to the distal femur slice showing both '
          'posterior condyles, then photograph the monitor with all four '
          'corners visible.',
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
      ],
      calibrate: false,
    ),
  ];

  Offset _unit(Offset v) => v / v.distance;

  /// Along the condylar line, and its normal pointing anterior (image up).
  (Offset, Offset) _axes(Map<String, Offset> mm) {
    final u = _unit(mm['lpc']! - mm['mpc']!);
    final n = Offset(-u.dy, u.dx);
    return (u, n.dy < 0 ? n : -n);
  }

  /// Version in degrees: positive anteversion, negative retroversion.
  double versionDegrees(Map<String, Offset> mm) {
    final (u, n) = _axes(mm);
    final d = mm['head']! - mm['neck']!;
    final along = (d.dx * u.dx + d.dy * u.dy).abs();
    final forward = d.dx * n.dx + d.dy * n.dy;
    return math.atan2(forward, along) * 180 / math.pi;
  }

  @override
  List<ResultLine> calculate(Map<String, Offset> mm) {
    final deg = versionDegrees(mm);
    final String grade;
    final Color color;
    if (deg < 0) {
      grade = 'Retroversion';
      color = Colors.redAccent;
    } else if (deg < 10) {
      grade = 'Decreased';
      color = Colors.orangeAccent;
    } else if (deg <= 20) {
      grade = 'Normal';
      color = Colors.greenAccent;
    } else {
      grade = 'Increased';
      color = Colors.orangeAccent;
    }
    return [
      ResultLine(
        deg >= 0 ? 'Anteversion' : 'Retroversion',
        '${deg.abs().toStringAsFixed(1)}°',
        color: color,
      ),
      // Reikerås; normal adult range taken as 10–20°.
      ResultLine('Grade', grade, color: color),
    ];
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

  /// Line through [a] and [b], extended [ext] times their distance each way.
  void _line(Canvas c, Offset a, Offset b, Paint p, {double ext = 1.5}) {
    final d = b - a;
    c.drawLine(a - d * ext, b + d * ext, p);
  }

  @override
  void paintGhost(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double s,
  ) {
    if (mm.containsKey('head') && !mm.containsKey('neck')) {
      final head = toPx(mm['head']!);
      _point(canvas, head, _img1Color, s);
      _label(canvas, head, 'Head centre (Image 1)', _img1Color, s);
    }
    if (mm.containsKey('head') && mm.containsKey('neck')) {
      final head = toPx(mm['head']!), neck = toPx(mm['neck']!);
      final ghost = Paint()
        ..color = _img1Color.withValues(alpha: 0.85)
        ..strokeWidth = 1.5 * s;
      _dashed(
        canvas,
        neck - (head - neck) * 2,
        head + (head - neck) * 2,
        ghost,
        s,
      );
      _point(canvas, head, _img1Color, s);
      _label(canvas, head, 'Neck axis (Image 1)', _img1Color, s);
    }
    if (mm.containsKey('mpc') && mm.containsKey('lpc')) {
      final a = toPx(mm['mpc']!), b = toPx(mm['lpc']!);
      final ghost = Paint()
        ..color = _img2Color.withValues(alpha: 0.85)
        ..strokeWidth = 1.5 * s;
      _dashed(canvas, a - (b - a) * 2, b + (b - a) * 2, ghost, s);
      _label(canvas, b, 'PCL (Image 2)', _img2Color, s);
    }
  }

  @override
  void paintCombined(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double s,
  ) {
    final head = toPx(mm['head']!), neck = toPx(mm['neck']!);
    final mpc = toPx(mm['mpc']!), lpc = toPx(mm['lpc']!);

    _line(
      canvas,
      mpc,
      lpc,
      Paint()
        ..color = _img2Color
        ..strokeWidth = 2 * s,
    );
    _line(
      canvas,
      neck,
      head,
      Paint()
        ..color = _img1Color
        ..strokeWidth = 2 * s,
    );

    // Parallel to the condylar line through the neck centre, and the arc
    // between it and the neck axis.
    final u = _unit(lpc - mpc);
    final toHead = head - neck;
    final side = (toHead.dx * u.dx + toHead.dy * u.dy) >= 0 ? u : -u;
    final ref = Paint()
      ..color = _resultColor
      ..strokeWidth = 1.5 * s;
    final r = math.max(toHead.distance, 60 * s);
    _dashed(canvas, neck - side * r * 0.3, neck + side * r * 1.3, ref, s);

    final a0 = math.atan2(side.dy, side.dx);
    final a1 = math.atan2(toHead.dy, toHead.dx);
    var sweep = a1 - a0;
    while (sweep > math.pi) {
      sweep -= 2 * math.pi;
    }
    while (sweep < -math.pi) {
      sweep += 2 * math.pi;
    }
    canvas.drawArc(
      Rect.fromCircle(center: neck, radius: r * 0.9),
      a0,
      sweep,
      false,
      Paint()
        ..color = _resultColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s,
    );
    final mid = a0 + sweep / 2;
    _label(
      canvas,
      // Just outside the arc, away from the head and neck labels.
      neck + Offset(math.cos(mid), math.sin(mid)) * (r * 0.9 + 14 * s),
      calculate(mm).first.value,
      _resultColor,
      s,
      shift: const Offset(4, -6),
    );

    for (final (p, c, l) in [
      (head, _img1Color, 'Head centre'),
      (neck, _img1Color, 'Neck centre'),
      (mpc, _img2Color, 'Medial PC'),
      (lpc, _img2Color, 'Lateral PC'),
    ]) {
      _point(canvas, p, c, s);
      _label(canvas, p, l, c, s);
    }
  }
}
