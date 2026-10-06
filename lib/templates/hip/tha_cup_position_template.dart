import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class ThaCupPositionTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'tha_cup_position';

  @override
  String get title => 'THA Cup Position';

  @override
  String get viewInfo => 'AP Pelvis';

  @override
  JointCategory get category => JointCategory.hip;

  @override
  IconData get icon => Icons.accessibility;

  @override
  String get infoDescription =>
      TemplateDescriptions.infoDescriptions['tha_cup_position'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(
      id: 'td_right',
      label: 'Right Teardrop',
      instruction: 'Mark inferior point of the right teardrop',
    ),
    const TemplateLandmark(
      id: 'td_left',
      label: 'Left Teardrop',
      instruction: 'Mark inferior point of the left teardrop',
    ),
    const TemplateLandmark(
      id: 'cup_rim_med',
      label: 'Cup Rim Medial',
      instruction: 'Mark the medial edge of the acetabular cup opening',
    ),
    const TemplateLandmark(
      id: 'cup_rim_lat',
      label: 'Cup Rim Lateral',
      instruction: 'Mark the lateral edge of the acetabular cup opening',
    ),
    const TemplateLandmark(
      id: 'cup_short_axis_1',
      label: 'Cup Ellipse Short Axis 1',
      instruction: 'Mark one endpoint of the projected cup ellipse short axis',
    ),
    const TemplateLandmark(
      id: 'cup_short_axis_2',
      label: 'Cup Ellipse Short Axis 2',
      instruction:
          'Mark the opposite endpoint of the projected cup ellipse short axis',
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

    final tdRight = p['td_right']!;
    final tdLeft = p['td_left']!;
    final cupMed = p['cup_rim_med']!;
    final cupLat = p['cup_rim_lat']!;
    final short1 = p['cup_short_axis_1']!;
    final short2 = p['cup_short_axis_2']!;

    final inclination = GeometryUtils.calculateCobbAngle(
      tdRight,
      tdLeft,
      cupMed,
      cupLat,
    );

    final longAxis = (cupLat - cupMed).distance;
    final shortAxis = (short2 - short1).distance;
    double? version;
    if (longAxis > 0) {
      final ratio = (shortAxis / longAxis).clamp(0.0, 1.0);
      version = asin(ratio) * 180 / pi;
    }

    return [
      'Cup Inclination: ${inclination.toStringAsFixed(1)}°',
      if (version != null)
        'Cup Version Approximation: ${version.toStringAsFixed(1)}°',
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
    final pPelvis = Paint()
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.55);
    final pCup = Paint()
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.cyanAccent;
    final pShort = Paint()
      ..strokeWidth = 1.5 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.yellowAccent;

    for (final pt in s) {
      canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }

    if (s.length >= 2) {
      paintExtendedLine(canvas, s[0], s[1], imageRect, pPelvis);
    }
    if (s.length >= 4) {
      canvas.drawLine(s[2], s[3], pCup);
      final center = (s[2] + s[3]) / 2;
      final radius = (s[3] - s[2]).distance / 2;
      canvas.drawCircle(
        center,
        radius,
        pCup..color = Colors.cyanAccent.withValues(alpha: 0.45),
      );
    }
    if (s.length >= 6) {
      canvas.drawLine(s[4], s[5], pShort);
    }
  }
}
