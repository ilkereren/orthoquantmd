import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class SpondylolisthesisTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'spondylolisthesis';

  @override
  String get title => 'Spondylolisthesis';

  @override
  String get viewInfo => 'Lateral Lumbar Spine';

  @override
  JointCategory get category => JointCategory.spine;

  @override
  IconData get icon => Icons.view_agenda_outlined;

  @override
  String get infoDescription =>
      TemplateDescriptions.infoDescriptions['spondylolisthesis'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(
      id: 'lower_post_sup',
      label: 'Lower Vertebra Post-Sup',
      instruction:
          'Mark posterior-superior corner of the LOWER vertebra (e.g. S1)',
    ),
    const TemplateLandmark(
      id: 'lower_ant_sup',
      label: 'Lower Vertebra Ant-Sup',
      instruction: 'Mark anterior-superior corner of the LOWER vertebra',
    ),
    const TemplateLandmark(
      id: 'upper_post_inf',
      label: 'Upper Vertebra Post-Inf',
      instruction:
          'Mark posterior-inferior corner of the SLIPPED vertebra (e.g. L5)',
    ),
    const TemplateLandmark(
      id: 'upper_ant_inf',
      label: 'Upper Vertebra Ant-Inf',
      instruction: 'Mark anterior-inferior corner of the SLIPPED vertebra',
    ),
    const TemplateLandmark(
      id: 'lower_post_inf',
      label: 'Lower Vertebra Posterior Wall',
      instruction:
          'Mark a caudal point on the posterior wall of the LOWER vertebra',
    ),
  ];

  static String meyerdingGrade(double slipPercent) {
    if (slipPercent < 0) return 'Retrolisthesis';
    if (slipPercent <= 25) return 'Grade I';
    if (slipPercent <= 50) return 'Grade II';
    if (slipPercent <= 75) return 'Grade III';
    if (slipPercent <= 100) return 'Grade IV';
    return 'Grade V (Spondyloptosis)';
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static Offset _unit(Offset v) {
    final d = v.distance;
    return d == 0 ? Offset.zero : v / d;
  }

  /// Signed segmental angle between the slipped vertebra's inferior endplate
  /// and the lower vertebra's superior endplate. Positive = lordosis.
  static double segmentalAngle(
    Offset lowerPost,
    Offset lowerAnt,
    Offset upperPost,
    Offset upperAnt,
  ) {
    final magnitude = GeometryUtils.calculateCobbAngle(
      lowerPost,
      lowerAnt,
      upperPost,
      upperAnt,
    );
    final u = _unit(lowerAnt - lowerPost);
    final toUpper = upperPost - lowerPost;
    final cranial = _unit(toUpper - u * _dot(toUpper, u));
    if (cranial == Offset.zero) return magnitude;
    final tilt = _dot(_unit(upperAnt - upperPost), cranial);
    return tilt >= 0 ? magnitude : -magnitude;
  }

  /// Boxall slip angle: slipped vertebra's inferior endplate vs. the line
  /// perpendicular to the lower vertebra's posterior wall.
  /// Positive = kyphotic (anterior end tilted caudally).
  static double slipAngle(
    Offset lowerPostSup,
    Offset lowerAntSup,
    Offset upperPost,
    Offset upperAnt,
    Offset lowerPostInf,
  ) {
    final cranial = _unit(lowerPostSup - lowerPostInf);
    var anterior = Offset(-cranial.dy, cranial.dx);
    if (_dot(anterior, lowerAntSup - lowerPostSup) < 0) anterior = -anterior;
    final e = _unit(upperAnt - upperPost);
    return atan2(_dot(e, -cranial), _dot(e, anterior)) * 180 / pi;
  }

  @override
  List<String> calculate(
    List<ReferencePoint> points,
    Rect imageRect, {
    double? pixelsPerMm,
  }) {
    if (imageRect.isEmpty) return [];
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];

    // Indices: 0:LowerPostSup, 1:LowerAntSup, 2:UpperPostInf,
    //          3:UpperAntInf, 4:LowerPostInf
    if (s.length >= 3) {
      final width = (s[1] - s[0]).distance;
      if (width > 0) {
        final slipPx = _dot(s[2] - s[0], _unit(s[1] - s[0]));
        final slipPercent = slipPx / width * 100;
        results.add('Slip: ${slipPercent.toStringAsFixed(1)}%');
        results.add('Meyerding: ${meyerdingGrade(slipPercent)}');
        if (pixelsPerMm != null && pixelsPerMm > 0) {
          results.add(
            'Slip Distance: ${(slipPx / pixelsPerMm).toStringAsFixed(1)} mm',
          );
        }
      }
    }

    if (s.length >= 4) {
      final seg = segmentalAngle(s[0], s[1], s[2], s[3]);
      results.add('Segmental Lordosis: ${seg.toStringAsFixed(1)}°');
    }

    if (s.length >= 5) {
      final sa = slipAngle(s[0], s[1], s[2], s[3], s[4]);
      results.add('Slip Angle: ${sa.toStringAsFixed(1)}°');
    }

    return results;
  }

  @override
  void paint(
    Canvas canvas,
    List<ReferencePoint> points,
    double scale,
    Paint paint,
    Rect imageRect,
  ) {
    if (points.isEmpty || imageRect.isEmpty) return;

    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final pLine = paint
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.cyanAccent;
    final pSlip = Paint()
      ..strokeWidth = 3.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.yellowAccent;
    final pHelper = Paint()
      ..strokeWidth = 1.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.7);
    final pWall = Paint()
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.greenAccent;
    final pPoint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (var pt in s) {
      canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }

    // Lower vertebra superior endplate
    if (s.length >= 2) paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);

    // Slip: projection of upper post-inf corner onto lower endplate
    if (s.length >= 3) {
      final proj = GeometryUtils.projectPointToLine(s[2], s[0], s[1]);
      paintDashedLine(canvas, s[2], proj, pHelper, dashWidth: 4, dashSpace: 3);
      canvas.drawLine(s[0], proj, pSlip);
    }

    // Slipped vertebra inferior endplate
    if (s.length >= 4) paintExtendedLine(canvas, s[2], s[3], imageRect, pLine);

    // Posterior wall + perpendicular reference for slip angle
    if (s.length >= 5) {
      paintExtendedLine(canvas, s[4], s[0], imageRect, pWall);
      final wall = s[0] - s[4];
      if (wall.distance > 0) {
        final perp = Offset(-wall.dy, wall.dx) / wall.distance;
        final len = (s[1] - s[0]).distance;
        paintDashedLine(canvas, s[0], s[0] + perp * len, pWall);
        paintDashedLine(canvas, s[0], s[0] - perp * len, pWall);
      }
    }
  }
}
