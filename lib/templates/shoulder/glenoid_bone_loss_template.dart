import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart'; // TemplateDescriptions
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class GlenoidBoneLossTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'glenoid_bone_loss';

  @override
  String get title => 'Glenoid Bone Loss';

  @override
  String get viewInfo => 'En Face 3D CT';
  
  @override
  JointCategory get category => JointCategory.shoulder;

  @override
  IconData get icon => Icons.accessibility_new;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['glenoid_bone_loss'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'glenoid_post', label: 'Posterior Rim', instruction: 'Mark posterior rim'),
    const TemplateLandmark(id: 'glenoid_inf', label: 'Inferior Rim', instruction: 'Mark inferior rim'),
    const TemplateLandmark(id: 'glenoid_third', label: '3rd Healthy Rim', instruction: 'Mark a third healthy glenoid rim'),
    const TemplateLandmark(id: 'glenoid_ant_defect', label: 'Ant Defect', instruction: 'Mark anterior glenoid defect edge'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
     if (imageRect.isEmpty || points.length < 4) return [];
     
     final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
     
     final res = GeometryUtils.calculateGlenoidDefect(screenPoints);
     if (res == null) return [];
     
     final loss = res['lossPercent'] as double;
     return ['Bone Loss: ${loss.toStringAsFixed(1)}%'];
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
    if (points.isEmpty || imageRect.isEmpty) return;
    
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();

    final paintCircle = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke..color = Colors.greenAccent;
    final paintPoint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
      
    for (var pt in screenPoints) {
       canvas.drawCircle(pt, 4.0/scale, paintPoint);
    }

     if (screenPoints.length >= 3) {
         final c = GeometryUtils.calculateCircleFrom3Points(
             screenPoints[0], screenPoints[1], screenPoints[2]
         );
         
         if (c != null) {
             canvas.drawCircle(c['center'], c['radius'], paintCircle);
             // Draw defect line if 4th point
             if (screenPoints.length >= 4) {
                 final paintDefect = Paint()..color = Colors.redAccent..strokeWidth = 2.0/scale..style = PaintingStyle.stroke;
                 canvas.drawLine(c['center'], screenPoints[3], paintDefect);
             }
         }
     }
  }
}
