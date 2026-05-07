import 'dart:math';
import 'package:flutter/material.dart';
import '../base/measurement_template_base.dart';
import '../../models/measurement_model.dart';
import '../../models/template_model.dart' hide Icons, TemplateDescriptions; // For JointCategory

class CarpalAlignmentTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'carpal_alignment';

  @override
  String get title => 'Carpal Alignment';

  @override
  String get viewInfo => 'Wrist AP X-Ray';

  @override
  JointCategory get category => JointCategory.hand;

  @override
  IconData get icon => Icons.back_hand;

  @override
  String get infoDescription => '''
**Carpal Alignment Analysis**

**1. Ulnar Variance:** Relative length difference between distal articular surfaces of Ulna and Radius. Positive (+) variance indicates the ulna is longer.

**2. Radial Inclination:** Angle of the radial articular surface relative to a line perpendicular to the radial shaft axis.

**3. Radial Height:** Distance between the tip of the radial styloid and the level of the ulnar articular surface (lunate fossa) of the radius.
''';

  @override
  List<TemplateLandmark> get landmarks => [
    TemplateLandmark(id: 'radius_axis_prox', label: 'Radius Shaft Prox', instruction: 'Mark Proximal Center of Radius Shaft'),
    TemplateLandmark(id: 'radius_axis_dist', label: 'Radius Shaft Dist', instruction: 'Mark Distal Center of Radius Shaft'),
    TemplateLandmark(id: 'ulna_distal', label: 'Ulna Distal', instruction: 'Mark Most Distal Point of Ulna Articular Surface'),
    TemplateLandmark(id: 'radius_lunate_fossa', label: 'Radius Lunate Fossa', instruction: 'Mark Most Distal Point of Radius Lunate Fossa'),
    TemplateLandmark(id: 'radial_styloid', label: 'Radial Styloid', instruction: 'Mark Tip of Radial Styloid'),
    TemplateLandmark(id: 'radius_ulnar_corner', label: 'Radius Ulnar Corner', instruction: 'Mark Ulnar Corner of Distal Radius'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (points.length < landmarks.length) return [];
    
    // Helper to denormalize
    Offset pos(Offset norm) {
       return Offset(
         imageRect.left + norm.dx * imageRect.width, 
         imageRect.top + norm.dy * imageRect.height
       );
    }

    // Map points for easier access
    final pMap = {for (int i = 0; i < landmarks.length; i++) landmarks[i].id: points[i].position};
    
    final rProx = pos(pMap['radius_axis_prox']!);
    final rDist = pos(pMap['radius_axis_dist']!);
    final uDist = pos(pMap['ulna_distal']!);
    final rLunate = pos(pMap['radius_lunate_fossa']!);
    final rStyloid = pos(pMap['radial_styloid']!);
    final rUlnarCorner = pos(pMap['radius_ulnar_corner']!);

    // 1. Ulnar Variance
    // Vector of Radius Axis
    final rAxis = rDist - rProx;
    final rAxisNorm = rAxis / rAxis.distance;
    
    // Ulnar Variance = Component of (uDist - rLunate) PARALLEL to Radius Axis.
    // Let's project vector (rLunate -> uDist) onto rAxisNorm.
    
    final radiusToUlna = uDist - rLunate;
    final uvProj = radiusToUlna.dx * rAxisNorm.dx + radiusToUlna.dy * rAxisNorm.dy; // Dot Product
    // If rAxis points Distally (Prox -> Dist), and Ulna is "longer" (more distal), product should be positive.

    // 2. Radial Inclination
    // Angle between (Radial Styloid -> Ulnar Corner) and Horizontal (Perpendicular to Radius Axis).
    final jointLine = rUlnarCorner - rStyloid;
    // Angle of Radius Axis
    final axisAngle = atan2(rAxis.dy, rAxis.dx);
    // Angle of Perpendicular (Reference Horizontal)
    final refAngle = axisAngle - pi / 2; // -90 deg
    
    // Angle of Joint Line
    final jointAngle = atan2(jointLine.dy, jointLine.dx);
    
    // Difference
    var riAngleRad = (jointAngle - refAngle).abs();
    if (riAngleRad > pi) riAngleRad = 2 * pi - riAngleRad; 
    // Usually acute angle
    if (riAngleRad > pi / 2) riAngleRad = pi - riAngleRad;
    
    // 3. Radial Height
    // Projected distance between Radial Styloid and Radius Lunate Fossa onto Axis
    // "Height" usually means vertical (axial) distance.
    final styloidToLunate = rLunate - rStyloid; // Vector pointing up (proximal) usually? 
    // Wait, Height is length.
    // Lunate is Proximal to Styloid. 
    // Styloid is distal tip. Lunate is fossa. Distance along axis.
    
    // Vector Styloid -> Lunate
    // Product with rAxisNorm.
    // rAxisNorm points Prox -> Distal?
    // rAxis = rDist - rProx; (Prox -> Dist)
    // So if Styloid (Distal) -> Lunate (Proximal), dot product is negative. 
    // We just want absolute distance along that axis.
    
    final heightVec = rStyloid - rLunate; // Lunate to Styloid
    final radialHeightPx = (heightVec.dx * rAxisNorm.dx + heightVec.dy * rAxisNorm.dy).abs();
    
    final riDeg = riAngleRad * 180 / pi;

    // Unit Conversion
    String uvResult;
    String rhResult;
    
    if (pixelsPerMm != null && pixelsPerMm! > 0) {
      final uvMm = uvProj / pixelsPerMm!;
      uvResult = 'Ulnar Variance: ${uvMm.toStringAsFixed(1)} mm';
      
      final rhMm = radialHeightPx / pixelsPerMm!;
      rhResult = 'Radial Height: ${rhMm.toStringAsFixed(1)} mm';
    } else {
      uvResult = 'Ulnar Variance: ${uvProj.toStringAsFixed(1)} px';
      rhResult = 'Radial Height: ${radialHeightPx.toStringAsFixed(1)} px';
    }

    return [
      uvResult,
      'Radial Inclination: ${riDeg.toStringAsFixed(1)}°',
      rhResult
    ];
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
    if (points.isEmpty) return;

    final count = min(points.length, landmarks.length);
    final pMap = {for (int i = 0; i < count; i++) landmarks[i].id: points[i].position};
    final paintObj = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..style = PaintingStyle.stroke;

    final auxPaint = Paint()
      ..color = paint.color.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
      
    final dashPaint = Paint()
      ..color = paint.color.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Helper to draw
    Offset? pos(String id) => pMap[id] != null ? denormalize(pMap[id]!, imageRect) : null;

    final rProx = pos('radius_axis_prox');
    final rDist = pos('radius_axis_dist');
    final uDist = pos('ulna_distal');
    final rLunate = pos('radius_lunate_fossa');
    final rStyloid = pos('radial_styloid');
    final rUlnarCorner = pos('radius_ulnar_corner');

    // 1. Draw Radius Axis (Base Reference)
    if (rProx != null && rDist != null) {
      canvas.drawLine(rProx, rDist, auxPaint);
      
      // Extend Axis visually
      paintExtendedLine(canvas, rProx, rDist, imageRect, dashPaint);

      final axisVec = rDist - rProx;
      final axisNorm = axisVec / axisVec.distance;
      final perpNorm = Offset(-axisNorm.dy, axisNorm.dx);
      const lineLen = 100.0; // Visual length
          
      // Ulnar Variance Reference Lines (Perpendicular to Axis)
      if (uDist != null && rLunate != null) {
         // Radial Reference Line (through rLunate) - Shared with Radial Height
         canvas.drawLine(rLunate - perpNorm * lineLen, rLunate + perpNorm * lineLen, paintObj);
         
         // Ulnar Reference Line (through uDist)
         canvas.drawLine(uDist - perpNorm * lineLen, uDist + perpNorm * lineLen, paintObj);
      }
      
      // Radial HEIGHT Reference Lines
      if (rStyloid != null && rLunate != null) {
          // rLunate line is already drawn above? If not, draw it?
          // It's checked in block above. Safe to redraw or verify.
          if (uDist == null) {
               canvas.drawLine(rLunate - perpNorm * lineLen, rLunate + perpNorm * lineLen, paintObj);
          }
          
          // Styloid Reference Line (Perpendicular)
          canvas.drawLine(rStyloid - perpNorm * lineLen, rStyloid + perpNorm * lineLen, paintObj);
      }
      
      // Radial Inclination Reference Area
      if (rStyloid != null && rUlnarCorner != null) {
          // Join Styloid and Ulnar Corner
          canvas.drawLine(rStyloid, rUlnarCorner, paintObj);
          
          // Draw perpendicular reference at Ulnar Corner (or Styloid) to show the angle
          paintDashedLine(canvas, rUlnarCorner - perpNorm * 80, rUlnarCorner + perpNorm * 80, dashPaint);
      }
    }
  }
}
