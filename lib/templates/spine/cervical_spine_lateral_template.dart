import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class CervicalSpineLateralTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'cervical_spine_lateral';

  @override
  String get title => 'Cervical Spine Lateral';

  @override
  String get viewInfo => 'Standing Lateral';

  @override
  JointCategory get category => JointCategory.spine;

  @override
  IconData get icon => Icons.format_align_center;

  @override
  String get infoDescription =>
      TemplateDescriptions.infoDescriptions['cervical_spine_lateral'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(
      id: 'c2_post_inf',
      label: 'C2 Inferior Endplate Posterior',
      instruction: 'Mark posterior corner of the C2 inferior endplate',
    ),
    const TemplateLandmark(
      id: 'c2_ant_inf',
      label: 'C2 Inferior Endplate Anterior',
      instruction: 'Mark anterior corner of the C2 inferior endplate',
    ),
    const TemplateLandmark(
      id: 'c7_post_inf',
      label: 'C7 Inferior Endplate Posterior',
      instruction: 'Mark posterior corner of the C7 inferior endplate',
    ),
    const TemplateLandmark(
      id: 'c7_ant_inf',
      label: 'C7 Inferior Endplate Anterior',
      instruction: 'Mark anterior corner of the C7 inferior endplate',
    ),
    const TemplateLandmark(
      id: 'c2_centroid',
      label: 'C2 Centroid',
      instruction: 'Mark the center of the C2 vertebral body',
    ),
    const TemplateLandmark(
      id: 'c7_post_sup',
      label: 'C7 Posterior Superior Corner',
      instruction: 'Mark the posterior-superior corner of C7',
    ),
    const TemplateLandmark(
      id: 't1_post_sup',
      label: 'T1 Superior Endplate Posterior',
      instruction: 'Mark posterior corner of the T1 superior endplate',
    ),
    const TemplateLandmark(
      id: 't1_ant_sup',
      label: 'T1 Superior Endplate Anterior',
      instruction: 'Mark anterior corner of the T1 superior endplate',
    ),
  ];

  @override
  List<String> calculate(
    List<ReferencePoint> points,
    Rect imageRect, {
    double? pixelsPerMm,
  }) {
    if (imageRect.isEmpty) return [];

    final p = {
      for (int i = 0; i < min(points.length, landmarks.length); i++)
        landmarks[i].id: denormalize(points[i].position, imageRect),
    };

    final results = <String>[];

    final c2PostInf = p['c2_post_inf'];
    final c2AntInf = p['c2_ant_inf'];
    final c7PostInf = p['c7_post_inf'];
    final c7AntInf = p['c7_ant_inf'];
    if (c2PostInf != null &&
        c2AntInf != null &&
        c7PostInf != null &&
        c7AntInf != null) {
      final lordosis = GeometryUtils.calculateCobbAngle(
        c2PostInf,
        c2AntInf,
        c7PostInf,
        c7AntInf,
      );
      results.add('C2-C7 Cobb Lordosis: ${lordosis.toStringAsFixed(1)}°');
    }

    final c2Centroid = p['c2_centroid'];
    final c7PostSup = p['c7_post_sup'];
    if (c2Centroid != null && c7PostSup != null) {
      final svaPx = c2Centroid.dx - c7PostSup.dx;
      if (pixelsPerMm != null && pixelsPerMm > 0) {
        results.add(
          'C2-C7 SVA: ${(svaPx / pixelsPerMm).toStringAsFixed(1)} mm',
        );
      } else {
        results.add('C2-C7 SVA: ${svaPx.toStringAsFixed(0)} px');
      }
    }

    final t1PostSup = p['t1_post_sup'];
    final t1AntSup = p['t1_ant_sup'];
    if (t1PostSup != null && t1AntSup != null) {
      final t1Slope = _angleToHorizontal(t1PostSup, t1AntSup);
      results.add('T1 Slope: ${t1Slope.toStringAsFixed(1)}°');
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
    final pPoint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    final pLine = Paint()
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.cyanAccent;
    final pSecondary = Paint()
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.yellowAccent;
    final pReference = Paint()
      ..strokeWidth = 1.2 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.55);

    for (final pt in s) {
      canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }

    if (s.length >= 2) {
      paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);
    }
    if (s.length >= 4) {
      paintExtendedLine(canvas, s[2], s[3], imageRect, pLine);
    }
    if (s.length >= 6) {
      final c2 = s[4];
      final c7 = s[5];
      paintDashedLine(
        canvas,
        Offset(c2.dx, imageRect.top),
        Offset(c2.dx, imageRect.bottom),
        pReference,
      );
      canvas.drawLine(c2, Offset(c2.dx, c7.dy), pSecondary);
      canvas.drawLine(Offset(c2.dx, c7.dy), c7, pSecondary);
    }
    if (s.length >= 8) {
      paintExtendedLine(canvas, s[6], s[7], imageRect, pSecondary);
      paintDashedLine(
        canvas,
        s[6],
        Offset(s[6].dx + 80 / scale, s[6].dy),
        pReference,
      );
    }
  }

  double _angleToHorizontal(Offset a, Offset b) {
    final v = b - a;
    if (v.distance == 0) return 0;
    var deg = atan2(v.dy, v.dx).abs() * 180 / pi;
    if (deg > 90) deg = 180 - deg;
    return deg.abs();
  }
}
