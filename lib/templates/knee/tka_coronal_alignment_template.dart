import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';

class TkaCoronalAlignmentTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'tka_coronal_alignment';

  @override
  String get title => 'TKA Component Alignment';

  @override
  String get viewInfo => 'Standing AP Knee';

  @override
  JointCategory get category => JointCategory.knee;

  @override
  IconData get icon => Icons.straighten;

  @override
  String get infoDescription =>
      TemplateDescriptions.infoDescriptions['tka_coronal_alignment'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(
      id: 'femur_axis_prox',
      label: 'Femur Axis Proximal',
      instruction: 'Mark center of the proximal visible femoral shaft',
    ),
    const TemplateLandmark(
      id: 'femur_axis_dist',
      label: 'Femur Axis Distal',
      instruction: 'Mark center of the distal femoral shaft',
    ),
    const TemplateLandmark(
      id: 'femoral_comp_med',
      label: 'Femoral Component Medial',
      instruction: 'Mark medial edge of the femoral component joint line',
    ),
    const TemplateLandmark(
      id: 'femoral_comp_lat',
      label: 'Femoral Component Lateral',
      instruction: 'Mark lateral edge of the femoral component joint line',
    ),
    const TemplateLandmark(
      id: 'tibial_comp_med',
      label: 'Tibial Component Medial',
      instruction: 'Mark medial edge of the tibial tray joint line',
    ),
    const TemplateLandmark(
      id: 'tibial_comp_lat',
      label: 'Tibial Component Lateral',
      instruction: 'Mark lateral edge of the tibial tray joint line',
    ),
    const TemplateLandmark(
      id: 'tibia_axis_prox',
      label: 'Tibia Axis Proximal',
      instruction: 'Mark center of the proximal tibial shaft',
    ),
    const TemplateLandmark(
      id: 'tibia_axis_dist',
      label: 'Tibia Axis Distal',
      instruction: 'Mark center of the distal visible tibial shaft',
    ),
  ];

  @override
  List<String> calculate(
    List<ReferencePoint> points,
    Rect imageRect, {
    double? pixelsPerMm,
  }) {
    if (imageRect.isEmpty || points.length < landmarks.length) return [];

    final p = {
      for (int i = 0; i < landmarks.length; i++)
        landmarks[i].id: denormalize(points[i].position, imageRect),
    };

    final femurAngle = _axisToComponentAngle(
      p['femur_axis_prox']!,
      p['femur_axis_dist']!,
      p['femoral_comp_med']!,
      p['femoral_comp_lat']!,
    );
    final tibiaAngle = _axisToComponentAngle(
      p['tibia_axis_prox']!,
      p['tibia_axis_dist']!,
      p['tibial_comp_med']!,
      p['tibial_comp_lat']!,
    );

    final femurDeviation = (90 - femurAngle).abs();
    final tibiaDeviation = (90 - tibiaAngle).abs();

    return [
      'Femoral Component Alignment: ${femurAngle.toStringAsFixed(1)}°',
      'Femoral Deviation From Perpendicular: ${femurDeviation.toStringAsFixed(1)}°',
      'Tibial Component Alignment: ${tibiaAngle.toStringAsFixed(1)}°',
      'Tibial Deviation From Perpendicular: ${tibiaDeviation.toStringAsFixed(1)}°',
    ];
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
    final pAxis = Paint()
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.cyanAccent;
    final pComponent = Paint()
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.yellowAccent;

    for (final pt in s) {
      canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }

    if (s.length >= 2) {
      paintExtendedLine(canvas, s[0], s[1], imageRect, pAxis);
    }
    if (s.length >= 4) {
      canvas.drawLine(s[2], s[3], pComponent);
    }
    if (s.length >= 6) {
      canvas.drawLine(s[4], s[5], pComponent);
    }
    if (s.length >= 8) {
      paintExtendedLine(canvas, s[6], s[7], imageRect, pAxis);
    }
  }

  double _axisToComponentAngle(
    Offset axisA,
    Offset axisB,
    Offset compA,
    Offset compB,
  ) {
    final axis = axisB - axisA;
    final comp = compB - compA;
    if (axis.distance == 0 || comp.distance == 0) return 0;

    final dot = axis.dx * comp.dx + axis.dy * comp.dy;
    final cosTheta = (dot / (axis.distance * comp.distance)).clamp(-1.0, 1.0);
    var angle = acos(cosTheta) * 180 / pi;
    if (angle > 90) angle = 180 - angle;
    return angle;
  }
}
