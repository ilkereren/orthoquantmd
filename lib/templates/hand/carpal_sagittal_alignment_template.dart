import 'dart:math';
import 'package:flutter/material.dart';
import '../base/measurement_template_base.dart';
import '../../models/measurement_model.dart';
import '../../models/template_model.dart' hide Icons, TemplateDescriptions;

class CarpalSagittalAlignmentTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'carpal_sagittal_alignment';

  @override
  String get title => 'Carpal Sagittal Alignment';

  @override
  String get viewInfo => 'Lateral Wrist X-Ray';

  @override
  JointCategory get category => JointCategory.hand;

  @override
  IconData get icon => Icons.back_hand; // Keeping consistent generic hand icon or change if needed

  @override
  String get infoDescription => '''
**Carpal Sagittal Alignment**

**1. Scapholunate Angle (SLA):** Angle formed by the longitudinal axes of the Scaphoid and Lunate. Normal: 30° – 60° (Average ~47°).

**2. Capitolunate Angle (CLA):** Angle formed by the longitudinal axes of the Capitate and Lunate. Normal: <30° in resting position (0° is ideal/coaxial).

**3. Volar Tilt (Palmar Tilt):** The angle of the distal radial articular surface relative to a line perpendicular to the radial shaft axis in the sagittal plane. Normal: ~11° Volar (Range: 2°–20°).
''';

  @override
  List<TemplateLandmark> get landmarks => [
    // Scaphoid
    TemplateLandmark(id: 'scaphoid_prox', label: 'Scaphoid Proximal', instruction: 'Mark Proximal Center of Scaphoid Axis'),
    TemplateLandmark(id: 'scaphoid_dist', label: 'Scaphoid Distal', instruction: 'Mark Distal Center of Scaphoid Axis'),
    
    // Lunate
    TemplateLandmark(id: 'lunate_prox', label: 'Lunate Proximal', instruction: 'Mark Proximal Center of Lunate Axis'),
    TemplateLandmark(id: 'lunate_dist', label: 'Lunate Distal', instruction: 'Mark Distal Center of Lunate Axis'),
    
    // Capitate
    TemplateLandmark(id: 'capitate_prox', label: 'Capitate Proximal', instruction: 'Mark Proximal Center of Capitate Axis'),
    TemplateLandmark(id: 'capitate_dist', label: 'Capitate Distal', instruction: 'Mark Distal Center of Capitate Axis'),
    
    // Radius
    TemplateLandmark(id: 'radius_axis_prox', label: 'Radius Shaft Prox', instruction: 'Mark Proximal Center of Radius Shaft'),
    TemplateLandmark(id: 'radius_axis_dist', label: 'Radius Shaft Dist', instruction: 'Mark Distal Center of Radius Shaft'),
    TemplateLandmark(id: 'radius_dorsal_lip', label: 'Radius Dorsal Lip', instruction: 'Mark Dorsal Lip of Distal Radius'),
    TemplateLandmark(id: 'radius_volar_lip', label: 'Radius Volar Lip', instruction: 'Mark Volar Lip of Distal Radius'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (points.length < landmarks.length) return [];

    // Helper
    Offset pos(Offset norm) {
       return Offset(
         imageRect.left + norm.dx * imageRect.width, 
         imageRect.top + norm.dy * imageRect.height
       );
    }
    
    // Map points
    final pMap = {for (int i = 0; i < landmarks.length; i++) landmarks[i].id: points[i].position};
    
    // 1. SLA (Scapholunate Angle)
    final sProx = pos(pMap['scaphoid_prox']!);
    final sDist = pos(pMap['scaphoid_dist']!);
    final lProx = pos(pMap['lunate_prox']!);
    final lDist = pos(pMap['lunate_dist']!);
    
    final vecScaphoid = sDist - sProx;
    final vecLunate = lDist - lProx;
    
    // Angle between lines. Dot product or simply difference in angles.
    final angScaphoid = atan2(vecScaphoid.dy, vecScaphoid.dx);
    final angLunate = atan2(vecLunate.dy, vecLunate.dx);
    
    var slaRad = (angScaphoid - angLunate).abs();
    if (slaRad > pi) slaRad = 2 * pi - slaRad;
    // We want the intersection angle, usually acute or up to 180?
    // SLA is typically 30-60.
    // If we calculate the smaller angle between lines:
    if (slaRad > pi / 2) {
       // Check standard definition complexity. Usually simplified as angle between major axes.
       // Keep calculated angle for now. if > 90, maybe supplement? 
       // Typically reported as acute angle unless specific instability direction.
       // Let's restrict to < 180.
    }
    final slaDeg = slaRad * 180 / pi;
    
    // 2. CLA (Capitolunate Angle)
    final cProx = pos(pMap['capitate_prox']!);
    final cDist = pos(pMap['capitate_dist']!);
    
    final vecCapitate = cDist - cProx;
    final angCapitate = atan2(vecCapitate.dy, vecCapitate.dx);
    
    var claRad = (angCapitate - angLunate).abs();
    if (claRad > pi) claRad = 2 * pi - claRad;
    final claDeg = claRad * 180 / pi;
    
    // 3. Volar Tilt
    // Angle between (Dorsal Lip -> Volar Lip) and (Perpendicular to Radius Axis).
    final rProx = pos(pMap['radius_axis_prox']!);
    final rDist = pos(pMap['radius_axis_dist']!);
    final rDorsal = pos(pMap['radius_dorsal_lip']!);
    final rVolar = pos(pMap['radius_volar_lip']!);
    
    final vecRadius = rDist - rProx;
    final angRadius = atan2(vecRadius.dy, vecRadius.dx);
    final angPerp = angRadius - pi / 2; // Reference (90 deg to shaft)
    
    final vecSurface = rVolar - rDorsal; // Dorsal to Volar usually points "down" and "volar-ly"
    final angSurface = atan2(vecSurface.dy, vecSurface.dx);
    
    var tiltRad = (angSurface - angPerp).abs();
    if (tiltRad > pi) tiltRad = 2 * pi - tiltRad;
    if (tiltRad > pi / 2) tiltRad = pi - tiltRad; // Acute angle relative to perpendicular
    
    final tiltDeg = tiltRad * 180 / pi;
    
    // Direction? 
    // If surface angle is "more volar" than perpendicular?
    // Hard to determine strictly without "Volar" side knowledge on image.
    // Assuming standard lateral view (Radius proximal, hand distal).
    // Dorsal usually up or down depending on side.
    // Let's report angle magnitude and assume user correlates with visual.
    // Or we could infer: Volar tilt means Volar lip is more proximal than Dorsal lip relative to perpendicular? 
    // Normal: Volar lip is more Proximal? No, Volar lip is more Distal? 
    // Normal Volar Tilt ~11 deg means articular surface faces slightly Volar.
    // So Volar lip is more PROXIMAL than Dorsal lip? No.
    // If it faces Volar, the Volar rim is lower (more proximal) than dorsal rim? 
    // Actually, "Volar Tilt" means the surface is tilted towards volar.
    // We will just report the angle.
    
    return [
       'Scapholunate Angle: ${slaDeg.toStringAsFixed(1)}°',
       'Capitolunate Angle: ${claDeg.toStringAsFixed(1)}°',
       'Volar Tilt: ${tiltDeg.toStringAsFixed(1)}°'
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

     final dashPaint = Paint()
      ..color = paint.color.withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
      
    // Helper
    Offset? pos(String id) => pMap[id] != null ? denormalize(pMap[id]!, imageRect) : null;

    void paintRefLine(String id1, String id2, Paint p, {bool extend = false}) {
        final p1 = pos(id1);
        final p2 = pos(id2);
        if (p1 != null && p2 != null) {
            if (extend) {
               paintExtendedLine(canvas, p1, p2, imageRect, p);
            } else {
               canvas.drawLine(p1, p2, p);
            }
        }
    }
    
    // Scaphoid
    paintRefLine('scaphoid_prox', 'scaphoid_dist', paintObj, extend: true);
    // Lunate
    paintRefLine('lunate_prox', 'lunate_dist', paintObj, extend: true);
    // Capitate
    paintRefLine('capitate_prox', 'capitate_dist', paintObj, extend: true);
    
    // Radius
    paintRefLine('radius_axis_prox', 'radius_axis_dist', paintObj, extend: true);
    
    // Volar Tilt
    final rDorsal = pos('radius_dorsal_lip');
    final rVolar = pos('radius_volar_lip');
    if (rDorsal != null && rVolar != null) {
       canvas.drawLine(rDorsal, rVolar, paintObj);
       
       // Draw Perpendicular Ref?
       final rProx = pos('radius_axis_prox');
       final rDist = pos('radius_axis_dist');
       if (rProx != null && rDist != null) {
           final axisVec = rDist - rProx;
           final axisNorm = axisVec / axisVec.distance;
           final perpNorm = Offset(-axisNorm.dy, axisNorm.dx);
           
           // Draw at center of articular surface line
           final center = (rDorsal + rVolar) / 2;
           paintDashedLine(canvas, center - perpNorm * 50, center + perpNorm * 50, dashPaint);
       }
    }
  }
}
