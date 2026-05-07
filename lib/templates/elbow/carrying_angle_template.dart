import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class CarryingAngleTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'carrying_angle';

  @override
  String get title => 'Carrying Angle';

  @override
  String get viewInfo => 'AP Elbow';

  @override
  JointCategory get category => JointCategory.elbow;

  @override
  IconData get icon => Icons.pan_tool_outlined;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['carrying_angle'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'humerus_prox', label: 'Humerus Mid-Shaft', instruction: 'Mark Center of Humerus Shaft (Proximal)'),
    const TemplateLandmark(id: 'humerus_dist', label: 'Humerus Distal', instruction: 'Mark Center of Humerus Distal End (Elbow Center)'),
    const TemplateLandmark(id: 'ulna_prox', label: 'Ulna Proximal', instruction: 'Mark Center of Ulna Proximal End (Elbow)'),
    const TemplateLandmark(id: 'ulna_dist', label: 'Ulna Distal', instruction: 'Mark Center of Ulna Distal Styloid'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    
    // Indices: 0:HumProx, 1:HumDist, 2:UlnaProx, 3:UlnaDist
    if (s.length >= 4) {
      final angle = GeometryUtils.calculateCobbAngle(s[0], s[1], s[2], s[3]);
      return ['Carrying Angle: ${angle.toStringAsFixed(1)}°'];
    }
    return [];
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
     if (points.isEmpty || imageRect.isEmpty) return;
     
     final s = points.map((p) => denormalize(p.position, imageRect)).toList();
     final pLine = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent;
     final pPoint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
     
     for (var pt in s) {
        canvas.drawCircle(pt, 4.0/scale, pPoint);
     }
     
     // Draw Humerus Line (extended)
     if (s.length >= 2) {
        paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);
     }
     
     // Draw Ulna Line (extended)
     if (s.length >= 4) {
        paintExtendedLine(canvas, s[2], s[3], imageRect, pLine);
     }
  }
}
