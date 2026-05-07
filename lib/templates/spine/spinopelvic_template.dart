import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class SpinopelvicTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'spinopelvic_parameters';

  @override
  String get title => 'Spinopelvic Parameters';

  @override
  String get viewInfo => 'Lateral Standing';

  @override
  JointCategory get category => JointCategory.spine;

  @override
  IconData get icon => Icons.format_align_center;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['spinopelvic_parameters'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 's1_post', label: 'S1 Post-Sup', instruction: 'Mark S1 Superior Endplate (Posterior Corner)'),
    const TemplateLandmark(id: 's1_ant', label: 'S1 Ant-Sup', instruction: 'Mark S1 Superior Endplate (Anterior Corner)'),
    const TemplateLandmark(id: 'r_hip_center', label: 'Right Hip Center', instruction: 'Mark Center of Right Femoral Head'),
    const TemplateLandmark(id: 'r_hip_rim', label: 'Right Hip Rim', instruction: 'Mark Point on Right Femoral Head Circumference'),
    const TemplateLandmark(id: 'l_hip_center', label: 'Left Hip Center', instruction: 'Mark Center of Left Femoral Head'),
    const TemplateLandmark(id: 'l_hip_rim', label: 'Left Hip Rim', instruction: 'Mark Point on Left Femoral Head Circumference'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    
    // Indices (0-based from landmarks list):
    // 0:S1Post, 1:S1Ant, 2:RHipC, 3:RHipR, 4:LHipC, 5:LHipR
    
    // Logic requires: S1Post, S1Ant, RHipC, LHipC
    // Indices: 0, 1, 2, 4.
    
    if (s.length >= 5) { // Need at least index 4
        // Check if points 2 and 4 exist.
        // Assuming sequence.
        
        final res = GeometryUtils.calculateSpinopelvic(s[0], s[1], s[2], s[4]);
        
        return [
           'Sacral Slope: ${res['SS']!.toStringAsFixed(1)}°',
           'Pelvic Tilt: ${res['PT']!.toStringAsFixed(1)}°',
           'Pelvic Incidence: ${res['PI']!.toStringAsFixed(1)}°',
        ];
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
     
     // S1 Line
     if (s.length >= 2) {
         canvas.drawLine(s[0], s[1], pLine);
     }
     
     // Hip Circles (Visual aid)
     // Right Hip
     if (s.length >= 4) {
         final center = s[2];
         final rim = s[3];
         canvas.drawCircle(center, (center-rim).distance, pLine..color=Colors.white30);
     }
     // Left Hip
     if (s.length >= 6) {
         final center = s[4];
         final rim = s[5];
         canvas.drawCircle(center, (center-rim).distance, pLine..color=Colors.white30);
     }
     
     // Connect Mid-S1 to Mid-Hip (Pelvic Radius)?
     if (s.length >= 5) {
         final midS1 = (s[0] + s[1]) / 2;
         final midHip = (s[2] + s[4]) / 2;
         canvas.drawLine(midS1, midHip, pLine..color=Colors.greenAccent);
         
         // Vertical from Hip Center? For PT visual.
         final vertEnd = Offset(midHip.dx, midHip.dy - (100 / scale)); // Up, scale adjusted
         paintDashedLine(canvas, midHip, vertEnd, Paint()..color=Colors.yellow..strokeWidth=1.5/scale..style=PaintingStyle.stroke);
     }
  }
}
