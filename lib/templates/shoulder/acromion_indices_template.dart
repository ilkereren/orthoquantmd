import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/models/measurement_model.dart'; // ReferencePoint
import 'package:ortho_quant_md/data/template_descriptions.dart'; // TemplateDescriptions
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class AcromionIndicesTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'critical_shoulder_angle';

  @override
  String get title => 'Acromion Indices';

  @override
  String get viewInfo => 'True AP (Grashey)';
  
  @override
  JointCategory get category => JointCategory.shoulder;

  @override
  IconData get icon => Icons.accessibility_new;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['critical_shoulder_angle'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'glenoid_sup', label: 'Glenoid Superior', instruction: 'Mark Superior Glenoid Margin'),
    const TemplateLandmark(id: 'glenoid_inf', label: 'Glenoid Inferior', instruction: 'Mark Inferior Glenoid Margin'),
    const TemplateLandmark(id: 'acromion_lat', label: 'Lateral Acromion', instruction: 'Mark Lateral Acromion Edge'),
    const TemplateLandmark(id: 'acromion_med', label: 'Medial Acromion', instruction: 'Mark Medial Acromion (Undersurface)'),
    const TemplateLandmark(id: 'humerus_lat', label: 'Lateral Humerus', instruction: 'Mark Lateral Humeral Head'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    // Denormalize points
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];
    
    // Indicies: 0:GS, 1:GI, 2:AL, 3:AM, 4:HL
    
    // 1. CSA: GS(0), GI(1), AL(2)
    if (screenPoints.length >= 3) {
      final csa = GeometryUtils.calculateAngle(screenPoints[0], screenPoints[1], screenPoints[2]);
      results.add('Critical Shoulder Angle: ${csa.toStringAsFixed(1)}°');
    }

    // 2. LAA: GS(0), GI(1), AM(3), AL(2)
    if (screenPoints.length >= 4) {
      // Logic assumes AM is index 3.
      final laa = GeometryUtils.calculateCobbAngle(screenPoints[0], screenPoints[1], screenPoints[3], screenPoints[2]);
      results.add('Lateral Acromion Angle: ${laa.toStringAsFixed(1)}°');
    }

    // 3. AI: GS(0), GI(1), AL(2), HL(4)
    if (screenPoints.length >= 5) {
      final ai = GeometryUtils.calculateAcromialIndex(screenPoints[0], screenPoints[1], screenPoints[2], screenPoints[4]);
      results.add('Acromial Index: ${ai.toStringAsFixed(2)}');
    }

    return results;
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
    if (points.isEmpty || imageRect.isEmpty) return;
    
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
    
    final pLine = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent;
    final pDashed = Paint()..strokeWidth = 1.5 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent.withOpacity(0.7);
    final pDist = Paint()..strokeWidth = 1.5 / scale..style = PaintingStyle.stroke..color = Colors.yellowAccent.withOpacity(0.8);

    // Draw Points
    final pPoint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    for (var pt in screenPoints) {
       canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }
    
    // Indices: 0:GS, 1:GI, 2:AL, 3:AM, 4:HL
    
    // 1. Glenoid Line (GS-GI) - Infinite Reference
    if (screenPoints.length >= 2) {
       paintExtendedLine(canvas, screenPoints[0], screenPoints[1], imageRect, pLine);
    }

    // 2. CSA Visualization (GI -> AL)
    if (screenPoints.length >= 3) {
       canvas.drawLine(screenPoints[1], screenPoints[2], pLine);
       
       // Dashed extension?
       final vec = screenPoints[2] - screenPoints[1]; // GI->AL
       final ext = screenPoints[2] + vec * 0.3; // Extend 30% past AL
       paintDashedLine(canvas, screenPoints[2], ext, pDashed);
    }
    
    // 3. LAA Visualization (AM-AL)
    if (screenPoints.length >= 4) {
       // Draw main segment
       canvas.drawLine(screenPoints[3], screenPoints[2], pLine);
       
       // Extend Medially to intersect Glenoid Line (approx)
       final vec = screenPoints[3] - screenPoints[2]; // AL->AM
       final ext = screenPoints[3] + vec * 1.5; 
       paintDashedLine(canvas, screenPoints[3], ext, pDashed);
    }

    // 4. AI Visualization (Distances to Glenoid Line)
    if (screenPoints.length >= 5) {
       // Need the Glenoid Line Vector
       final gs = screenPoints[0];
       final gi = screenPoints[1];
       final al = screenPoints[2];
       final hl = screenPoints[4];

       final gVec = gi - gs;
       if (gVec.distance > 0) {
           final gNorm = gVec / gVec.distance;
           
           // Project AL onto Glenoid Line (GS + t * gNorm)
           // Vector GS->AL
           final gs_al = al - gs;
           final t_al = gs_al.dx * gNorm.dx + gs_al.dy * gNorm.dy;
           final p_al = gs + gNorm * t_al; // Projection point on line
           
           // Project HL
           final gs_hl = hl - gs;
           final t_hl = gs_hl.dx * gNorm.dx + gs_hl.dy * gNorm.dy;
           final p_hl = gs + gNorm * t_hl;
           
           // Draw distances (Horizontal-ish lines)
           paintDashedLine(canvas, al, p_al, pDist);
           paintDashedLine(canvas, hl, p_hl, pDist);
       }
    }
  }
}
