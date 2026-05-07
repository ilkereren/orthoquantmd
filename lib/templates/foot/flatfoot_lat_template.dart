import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class FlatfootLatTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'flatfoot_lat';

  @override
  String get title => 'Flatfoot';

  @override
  String get viewInfo => 'Standing Lateral';

  @override
  JointCategory get category => JointCategory.foot;

  @override
  IconData get icon => Icons.do_not_step;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['flatfoot_lat'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'talus_prox', label: 'Talus Proximal', instruction: 'Mark Center of Talus Body'),
    const TemplateLandmark(id: 'talus_dist', label: 'Talus Distal', instruction: 'Mark Center of Talus Head'),
    const TemplateLandmark(id: 'm1_prox', label: 'M1 Base', instruction: 'Mark Center of M1 Base'),
    const TemplateLandmark(id: 'm1_dist', label: 'M1 Head', instruction: 'Mark Center of M1 Head'),
    const TemplateLandmark(id: 'calc_inf_post', label: 'Calcaneus Post Inf', instruction: 'Mark Posterior Point of Calcaneal Inferior Surface'),
    const TemplateLandmark(id: 'calc_inf_ant', label: 'Calcaneus Ant Inf', instruction: 'Mark Anterior Point of Calcaneal Inferior Surface'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];
    
    // Indices: 0:TalusP, 1:TalusD, 2:M1P, 3:M1D, 4:CalcP, 5:CalcA
    
    // Meary's: Talus(0-1) vs M1(2-3)
    if (s.length >= 4) {
       final meary = GeometryUtils.calculateCobbAngle(s[0], s[1], s[2], s[3]);
       results.add("Meary's Angle: ${meary.toStringAsFixed(1)}°");
    }
    
    // Calcaneal Pitch: Calc(4-5) vs Horizontal
    if (s.length >= 6) {
       final pitch = GeometryUtils.calculateSacralSlope(s[4], s[5]); // Uses atan relative to horiz
       results.add("Calcaneal Pitch: ${pitch.toStringAsFixed(1)}°");
       
       // Talocalcaneal: Talus(0-1) vs Calc(4-5)
       final tca = GeometryUtils.calculateCobbAngle(s[0], s[1], s[4], s[5]);
       results.add("Talocalcaneal: ${tca.toStringAsFixed(1)}°");
    }

    return results;
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
     
     // 0-1 Talus Axis
     if (s.length >= 2) paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);
     
     // 2-3 M1 Axis
     if (s.length >= 4) paintExtendedLine(canvas, s[2], s[3], imageRect, pLine);
     
     // 4-5 Calcaneal Axis
     if (s.length >= 6) {
         paintExtendedLine(canvas, s[4], s[5], imageRect, pLine);
     }
  }
}
