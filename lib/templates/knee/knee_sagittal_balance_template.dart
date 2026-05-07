import 'dart:math';
import 'package:flutter/material.dart';
import '../base/measurement_template_base.dart';
import '../../models/measurement_model.dart';
import '../../models/template_model.dart' hide Icons, TemplateDescriptions;
import '../../utils/geometry.dart';

class KneeSagittalBalanceTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'knee_sagittal_balance';

  @override
  String get title => 'Knee Arthroplasty – Sagittal Balance';

  @override
  String get viewInfo => 'Lateral Knee Radiograph';

  @override
  JointCategory get category => JointCategory.knee;

  @override
  IconData get icon => Icons.straighten;

  @override
  String get infoDescription => '''
**Knee Arthroplasty – Sagittal Balance**

**1. Posterior Tibial Slope (PTS):** Angle between the tibial component articular surface and the line perpendicular to the tibial anatomical axis.
Significance: Positive (+) indicates posterior slope.
Note: Increased slope generally improves flexion range.

**2. Femoral Component Flexion Angle (FCFA):** Angle between the distal femoral anatomical axis and the femoral component in the sagittal plane.
Interpretation: Positive (+) = Flexion, Negative (-) = Extension.
Target: Usually 0°–3° flexion to prevent anterior notching.

**3. Posterior Femoral Condylar Offset (PFCO):** The maximum distance from the tangent of the posterior femoral cortex to the most posterior aspect of the femoral component condyles.
Significance: Restoration of PFCO is critical for maximizing knee flexion.
''';

  @override
  List<TemplateLandmark> get landmarks => [
    // Femur Axis
    TemplateLandmark(id: 'femur_shaft_prox', label: 'Femur Shaft Proximal', instruction: 'Mark center of proximal femur shaft'),
    TemplateLandmark(id: 'femur_shaft_dist', label: 'Femur Shaft Distal', instruction: 'Mark center of distal femur shaft'),
    
    // Femoral Component
    TemplateLandmark(id: 'femur_comp_ant', label: 'Femoral Distal Surface Anterior', instruction: 'Mark anterior point of the femoral component\'s distal flat surface'),
    TemplateLandmark(id: 'femur_comp_post', label: 'Femoral Distal Surface Posterior', instruction: 'Mark posterior point of the femoral component\'s distal flat surface'),
    
    // Posterior Offset
    TemplateLandmark(id: 'post_condyle', label: 'Posterior Condyle Edge', instruction: 'Mark most posterior point of femoral component contour'),

    // Tibial Component
    TemplateLandmark(id: 'tibia_comp_ant', label: 'Tibial Component Anterior', instruction: 'Mark anterior edge of tibial component surface'),
    TemplateLandmark(id: 'tibia_comp_post', label: 'Tibial Component Posterior', instruction: 'Mark posterior edge of tibial component surface'),

    // Tibia Axis
    TemplateLandmark(id: 'tibia_shaft_prox', label: 'Tibia Shaft Proximal', instruction: 'Mark center of proximal tibia shaft'),
    TemplateLandmark(id: 'tibia_shaft_dist', label: 'Tibia Shaft Distal', instruction: 'Mark center of distal tibia shaft'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (points.length < landmarks.length) return [];

    final p = {for (int i = 0; i < landmarks.length; i++) landmarks[i].id: denormalize(points[i].position, imageRect)};

    final tShaftProx = p['tibia_shaft_prox']!;
    final tShaftDist = p['tibia_shaft_dist']!;
    final fShaftProx = p['femur_shaft_prox']!;
    final fShaftDist = p['femur_shaft_dist']!;
    final tCompAnt = p['tibia_comp_ant']!;
    final tCompPost = p['tibia_comp_post']!;
    final fCompAnt = p['femur_comp_ant']!;
    final fCompPost = p['femur_comp_post']!;
    final postCondyle = p['post_condyle']!;

    // 1. PTS
    // Tibia Axis
    final vTibia = tShaftDist - tShaftProx;
    // Component Axis
    final vTComp = tCompPost - tCompAnt;
    
    // Angle between them. Orthogonal is 90. PTS is the deviation from 90.
    double angleTibiaComp = (atan2(vTibia.dy, vTibia.dx) - atan2(vTComp.dy, vTComp.dx)).abs();
    if (angleTibiaComp > pi) angleTibiaComp = 2 * pi - angleTibiaComp;
    double pts = (90 - (angleTibiaComp * 180 / pi)).abs();

    // 2. FCFA
    // Femur Axis (Prox to Dist)
    final vFemur = fShaftDist - fShaftProx;
    // Component Distal Surface (Ant to Post)
    final vFComp = fCompPost - fCompAnt;
    
    // deviation from 90 deg. 
    double angleFemurComp = (atan2(vFemur.dy, vFemur.dx) - atan2(vFComp.dy, vFComp.dx)).abs();
    if (angleFemurComp > pi) angleFemurComp = 2 * pi - angleFemurComp;
    // Flexion (+) means posterior is higher relative to axis -> angle < 90
    double fcfa = 90 - (angleFemurComp * 180 / pi);

    // 3. PFCO
    final proj = GeometryUtils.projectPointToLine(postCondyle, fShaftProx, fShaftDist);
    double pfcoPx = (postCondyle - proj).distance;
    double pfcoMm = (pixelsPerMm != null && pixelsPerMm > 0) ? pfcoPx / pixelsPerMm : pfcoPx;

    final unit = pixelsPerMm != null ? 'mm' : 'px';

    return [
      'Posterior Tibial Slope: ${pts.toStringAsFixed(1)}°',
      'Femoral Component Flexion Angle: ${fcfa.toStringAsFixed(1)}°',
      'Posterior Femoral Condylar Offset: ${pfcoMm.toStringAsFixed(1)} $unit',
    ];
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
    if (points.isEmpty) return;

    final count = min(points.length, landmarks.length);
    final pMap = {for (int i = 0; i < count; i++) landmarks[i].id: denormalize(points[i].position, imageRect)};

    final paintMain = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..style = PaintingStyle.stroke;

    final paintDash = Paint()
      ..color = paint.color.withOpacity(0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final paintComp = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // 1. Tibia Axis
    if (pMap.containsKey('tibia_shaft_prox') && pMap.containsKey('tibia_shaft_dist')) {
      final p1 = pMap['tibia_shaft_prox']!;
      final p2 = pMap['tibia_shaft_dist']!;
      canvas.drawLine(p1, p2, paintMain);
      paintExtendedLine(canvas, p1, p2, imageRect, paintDash);
    }

    // 2. Femur Axis
    if (pMap.containsKey('femur_shaft_prox') && pMap.containsKey('femur_shaft_dist')) {
      final p1 = pMap['femur_shaft_prox']!;
      final p2 = pMap['femur_shaft_dist']!;
      canvas.drawLine(p1, p2, paintMain);
      paintExtendedLine(canvas, p1, p2, imageRect, paintDash);
    }

    // 3. Tibial Component
    if (pMap.containsKey('tibia_comp_ant') && pMap.containsKey('tibia_comp_post')) {
      final p1 = pMap['tibia_comp_ant']!;
      final p2 = pMap['tibia_comp_post']!;
      canvas.drawLine(p1, p2, paintComp);
    }

    // 4. Femoral Component
    if (pMap.containsKey('femur_comp_ant') && pMap.containsKey('femur_comp_post')) {
      final p1 = pMap['femur_comp_ant']!;
      final p2 = pMap['femur_comp_post']!;
      canvas.drawLine(p1, p2, paintComp);
    }

    // 5. PFCO Offset line
    if (pMap.containsKey('post_condyle') && pMap.containsKey('femur_shaft_prox') && pMap.containsKey('femur_shaft_dist')) {
      final pc = pMap['post_condyle']!;
      final pf1 = pMap['femur_shaft_prox']!;
      final pf2 = pMap['femur_shaft_dist']!;
      final proj = GeometryUtils.projectPointToLine(pc, pf1, pf2);
      canvas.drawLine(pc, proj, paintComp..strokeWidth = 1.5);
      canvas.drawCircle(pc, 3.0/scale, paintComp..style = PaintingStyle.fill);
    }
  }
}
