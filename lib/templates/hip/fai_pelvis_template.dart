import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/measurement_model.dart';
import '../../models/template_model.dart' hide Icons, TemplateDescriptions;
import '../../utils/geometry.dart';
import '../base/measurement_template_base.dart';

class FaiPelvisTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'fai_pelvis';

  @override
  String get title => 'FAI – AP Pelvis';

  @override
  String get viewInfo => 'AP Pelvis';

  @override
  JointCategory get category => JointCategory.hip;

  @override
  IconData get icon => Icons.accessibility;

  @override
  String get infoDescription => """
**FAI – AP Pelvis**

**LCEA (Wiberg) — Lateral Center-Edge Angle**
Superolateral femoral head coverage.
- **Landmarks:** Center of Femoral Head (C) + Lateral Edge of the Sourcil.
- **Measurement:** Angle between the vertical axis (perpendicular to the inter-teardrop line) and line C-L.
- **Normal:** 25°–39°.
- **Pathology:** Dysplasia <20° | Borderline 20°–25° | Pincer-type FAI >40°.

**Tönnis Angle (Acetabular Index)**
Inclination of the weight-bearing acetabular roof.
- **Landmarks:** Pelvic Horizontal Axis (Inter-teardrop line) + Medial/Lateral edges of the Sourcil.
- **Measurement:** Angle formed between the horizontal axis and the slope of the sourcil.
- **Normal:** 0°–10°.
- **Pathology:** Dysplasia >10° (Steep) | Pincer-type FAI <0° (Negative/Reverse slope).
""";

  @override
  List<TemplateLandmark> get landmarks => [
        // Pelvic Orientation
        TemplateLandmark(id: 'teardrop_r', label: 'Right Teardrop', instruction: 'Mark Inferior point of Right Teardrop (Pelvic Ref)'),
        TemplateLandmark(id: 'teardrop_l', label: 'Left Teardrop', instruction: 'Mark Inferior point of Left Teardrop (Pelvic Ref)'),

        // Femoral Head (3 points for circle)
        TemplateLandmark(id: 'fh_1', label: 'Head Cortex 1', instruction: 'Mark a point on Femoral Head cortex'),
        TemplateLandmark(id: 'fh_2', label: 'Head Cortex 2', instruction: 'Mark a point on Femoral Head cortex'),
        TemplateLandmark(id: 'fh_3', label: 'Head Cortex 3', instruction: 'Mark a point on Femoral Head cortex'),

        // Sourcil
        TemplateLandmark(id: 'sourcil_med', label: 'Medial Sourcil', instruction: 'Mark Medial Edge of Weight-Bearing Dome'),
        TemplateLandmark(id: 'sourcil_lat', label: 'Lateral Sourcil', instruction: 'Mark Lateral Edge of Weight-Bearing Dome'),
      ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    List<String> results = [];

    // LCEA Calc (Need first 6 points) - 0,1,2,3,4,6 ?? Wait, indexes depend on landmarks list.
    // Landmarks: 0:TR, 1:TL, 2:FH1, 3:FH2, 4:FH3, 5:S_Med, 6:S_Lat
    // Actually LCEA needs: TR, TL, FH... and Sourcil Lat (Index 6)
    
    // We normalize points to image rect for calculation? 
    // GeometryUtils usually expects SCREEN coordinates or Image coordinates? 
    // Usually we pass points that are in the same coordinate space.
    // Let's use image coordinates (denormalized).

    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();

    if (screenPoints.length >= 7) {
       // LCEA
       // Indices: TR=0, TL=1, FH=2,3,4, SLat=6
       final lcea = GeometryUtils.calculateLCEA(
         screenPoints[0], screenPoints[1], 
         screenPoints[2], screenPoints[3], screenPoints[4], 
         screenPoints[6]
       );
       results.add("LCEA: ${lcea.toStringAsFixed(1)}°");

       // Tönnis
       // Indices: TR=0, TL=1, SMed=5, SLat=6
       final tonnis = GeometryUtils.calculateTonnisAngle(
         screenPoints[0], screenPoints[1], 
         screenPoints[5], screenPoints[6]
       );
       results.add("Tönnis: ${tonnis.toStringAsFixed(1)}°");
    }

    return results;
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
    if (points.isEmpty || imageRect.isEmpty) return;
    
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
    final p = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke;
    
    // Draw Landmarks
    for (var pt in screenPoints) {
       canvas.drawCircle(pt, 3.0 / scale, p..style=PaintingStyle.fill);
       p.style = PaintingStyle.stroke; // reset
    }

    // 1. Draw Pelvic Horizontal (Teardrops) - if we have first 2
    if (screenPoints.length >= 2) {
       canvas.drawLine(screenPoints[0], screenPoints[1], p..color=p.color.withValues(alpha:0.5));
    }

    // 2. Draw Femoral Head Circle - if we have FH points (2,3,4)
    if (screenPoints.length >= 5) {
       final fhCenter = GeometryUtils.getCircleCenter(screenPoints[2], screenPoints[3], screenPoints[4]);
       if (fhCenter != Offset.zero) {
           final r = (screenPoints[2] - fhCenter).distance;
           canvas.drawCircle(fhCenter, r, p..color=p.color.withValues(alpha:0.5));
           canvas.drawCircle(fhCenter, 3.0/scale, p..style=PaintingStyle.fill); 
           p.style=PaintingStyle.stroke;

           // 3. Draw LCEA logic (Vertical + Center-Edge)
           // If we have Sourcil Lat (Index 6)
           if (screenPoints.length >= 7) {
               // Vertical Reference
               final vPelvis = screenPoints[1] - screenPoints[0];
               // Rotated 90
               var vVert = Offset(vPelvis.dy, -vPelvis.dx);
               if (vVert.dy > 0) vVert = -vVert; // Force Up
               
               final vLineEnd = fhCenter + (vVert / vVert.distance) * (100.0/scale);
               _drawDashedLine(canvas, fhCenter, vLineEnd, p..strokeWidth=1.5/scale);
               
               // Center-Edge Line
               canvas.drawLine(fhCenter, screenPoints[6], p..strokeWidth=2.0/scale);
           }
       }
    }

    // 4. Draw Tönnis Logic (Sourcil Slope) - if we have SMed(5) and SLat(6)
    if (screenPoints.length >= 7) {
        canvas.drawLine(screenPoints[5], screenPoints[6], p..strokeWidth=2.0/scale..color=Colors.yellow);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    var path = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy);
    // Simple dash logic or use standard one if available. 
    // For now, simple line for MVP, or reuse GeometryUtils dash if I move it there.
    // Let's implement simple dash here to be self-contained.
    
    final double dashWidth = 5.0;
    final double dashSpace = 5.0;
    double distance = (p2 - p1).distance;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;
    
    double currentDistance = 0;
    while (currentDistance < distance) {
        canvas.drawLine(
            Offset(p1.dx + dx * currentDistance, p1.dy + dy * currentDistance),
            Offset(p1.dx + dx * min(currentDistance + dashWidth, distance), 
                   p1.dy + dy * min(currentDistance + dashWidth, distance)),
            paint
        );
        currentDistance += dashWidth + dashSpace;
    }
  }
  
  double min(double a, double b) => a < b ? a : b;
}
