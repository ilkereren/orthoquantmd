import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart'; // TemplateDescriptions
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class GlenoidPlanningApTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'glenoid_planning_ap';

  @override
  String get title => 'Glenoid Planning';

  @override
  String get viewInfo => 'True AP (Grashey)';

  @override
  JointCategory get category => JointCategory.shoulder;

  @override
  IconData get icon => Icons.architecture;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['glenoid_planning_ap'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'ss_med', label: 'SS Fossa Med (A)', instruction: 'Place Medial point of SS Fossa'),
    const TemplateLandmark(id: 'ss_lat', label: 'SS Fossa Lat (B)', instruction: 'Place Lateral point of SS Fossa'),
    const TemplateLandmark(id: 'gl_inf', label: 'Glenoid Inf (C)', instruction: 'Place Inferior margin of Glenoid'),
    const TemplateLandmark(id: 'gl_int', label: 'Glenoid Int (D)', instruction: 'Place Glenoid intersection point'),
    const TemplateLandmark(id: 'gl_sup', label: 'Glenoid Sup (E)', instruction: 'Place Superior margin of Glenoid'),
    const TemplateLandmark(id: 'ac_lat', label: 'Acromion Lat (F)', instruction: 'Place Lateral point of Acromion'),
    const TemplateLandmark(id: 'maj_tub', label: 'Major Tub (G)', instruction: 'Place point on Major Tubercule'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    // Landmarks: 0:ss_med, 1:ss_lat, 2:gl_inf, 3:gl_int, 4:gl_sup, 5:ac_lat, 6:maj_tub
    
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];
    
    // Need at least SS Line (0,1) and Glenoid Inf (2) for Reference
    if (screenPoints.length >= 3) {
       // Reference Axis: Perpendicular to SS Fossa (0->1)
       // We normalize vector 0->1, rotate 90 deg.
       final ssVec = screenPoints[1] - screenPoints[0];
       // Check if vertical or horizontal? Usually SS Fossa is roughly horizontal on AP.
       // Perpendicular points "Down" ideally.
       // Standard: Perpendicular to Scapular axis.
    }
    
    // Helper to get angle with vertical/horizontal or relative
    // RSA: Angle between Line(C->D) and Perpendicular to Line(A->B)
    if (screenPoints.length >= 4) {
       // A=0, B=1, C=2, D=3
       final vecSS = screenPoints[1] - screenPoints[0];
       final vecRSA = screenPoints[3] - screenPoints[2]; // C->D
       
       // Angle between vectors
       // We want angle relative to perpendicular. 
       // Angle(SS) - Angle(RSA) gives angle between lines.
       // We want (Angle(SS) + 90) - Angle(RSA).
       
       final angSS = atan2(vecSS.dy, vecSS.dx);
       final angPerp = angSS + pi / 2; // Normal axis
       final angRSA = atan2(vecRSA.dy, vecRSA.dx);
       
       // Calculate deviation from Perpendicular
       double rsaDeg = (angRSA - angPerp) * 180 / pi;
       // Normalize to -90..90 or 0..180
       // RSA is inclination. 0 means neutral (vertical/perp).
       // Standard reporting: value in degrees.
       // Usually magnitude is reported, or sign for superior/inferior tilt.
       // Let's report absolute deviation from perpendicular? 
       // Or the angle itself? Description: "Angle between... and ..."
       // If perfectly perp, angle is 0. 
       // If we use GeometryUtils, we need points. 
       
       // Let's implement manually for clarity.
       // Angle between two lines:
       double angleDiff = (angRSA - angPerp).abs();
       if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
       if (angleDiff > pi / 2) angleDiff = pi - angleDiff; // Acute angle
       
       results.add('Reverse Shoulder Angle: ${ (angleDiff * 180 / pi).toStringAsFixed(1) }°');
    }
    
    // ASA: Angle between Line(C->E) and Perpendicular to Line(A->B)
    if (screenPoints.length >= 5) {
       final vecSS = screenPoints[1] - screenPoints[0];
       final vecASA = screenPoints[4] - screenPoints[2]; // C->E
       
       final angSS = atan2(vecSS.dy, vecSS.dx);
       final angPerp = angSS + pi / 2;
       final angASA = atan2(vecASA.dy, vecASA.dx);
       
       double angleDiff = (angASA - angPerp).abs();
       if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
       if (angleDiff > pi / 2) angleDiff = pi - angleDiff;
       
       results.add('Anatomic Shoulder Angle: ${ (angleDiff * 180 / pi).toStringAsFixed(1) }°');
    }

    // Lat Angle: maj_tub(6) -> ac_lat(5) -> gl_sup(4)
    // Angle at F (5)
    if (screenPoints.length >= 7) {
       final lat = GeometryUtils.calculateAngle(screenPoints[6], screenPoints[5], screenPoints[4]);
       results.add('Lateralization Angle: ${lat.toStringAsFixed(1)}°');
    }

    // Dist Angle: ac_lat(5) -> gl_sup(4) -> maj_tub(6)
    // Angle at E (4)
    if (screenPoints.length >= 7) {
       final dist = GeometryUtils.calculateAngle(screenPoints[5], screenPoints[4], screenPoints[6]);
       results.add('Distalization Angle: ${dist.toStringAsFixed(1)}°');
    }
    
    return results;
  }
  
  // Helper to resolve parameter mismatch in map creation above
  // (Not used in final logic, removed)

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
     if (points.isEmpty || imageRect.isEmpty) return;
     
     final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
     final pLine = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent;
     final pDashed = Paint()..strokeWidth = 1.5 / scale..style = PaintingStyle.stroke..color = Colors.yellowAccent.withOpacity(0.8);
     final pRef = Paint()..strokeWidth = 1.0 / scale..style = PaintingStyle.stroke..color = Colors.white.withOpacity(0.5);
     
     final pPoint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
     
    for (var pt in screenPoints) {
       canvas.drawCircle(pt, 4.0/scale, pPoint);
    }
    
    // 1. Draw SS Fossa Line (A-B)
    if (screenPoints.length >= 2) {
         // Use the new centralized helper for infinite extension
         paintExtendedLine(canvas, screenPoints[0], screenPoints[1], imageRect, pLine);
         
         final vecSS = screenPoints[1] - screenPoints[0];
         if (vecSS.distance > 0) {
            final normSS = vecSS / vecSS.distance;
            
            // Reference Axis (Perpendicular) at C (2)
             if (screenPoints.length >= 3) {
                 final perp = Offset(-normSS.dy, normSS.dx);
                 
                 // Draw perpendicular passing through C (2)
                 const len = 100.0;
                 paintDashedLine(canvas, screenPoints[2] - perp * len, screenPoints[2] + perp * len, pRef);
             }
         }
    }
    
    // RSA Line: C(2)->D(3)
    if (screenPoints.length >= 4) {
         canvas.drawLine(screenPoints[2], screenPoints[3], pLine);
    }
    
    // ASA Line: C(2)->E(4)
    if (screenPoints.length >= 5) {
         canvas.drawLine(screenPoints[2], screenPoints[4], pLine);
    }
    
    // Lat/Dist Lines: F(5), G(6), E(4)
    if (screenPoints.length >= 7) {
         // F-G
         canvas.drawLine(screenPoints[5], screenPoints[6], pLine);
         // F-E
         canvas.drawLine(screenPoints[5], screenPoints[4], pLine);
         // E-G (Reference)
         canvas.drawLine(screenPoints[4], screenPoints[6], pLine);
    }
  }
}
