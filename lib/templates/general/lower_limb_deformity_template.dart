import 'dart:math';
import 'package:flutter/material.dart';
import '../base/measurement_template_base.dart';
import '../../models/measurement_model.dart';
import '../../models/template_model.dart' hide Icons, TemplateDescriptions;
import '../../utils/geometry.dart';

class LowerLimbDeformityTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'lower_limb_deformity';

  @override
  String get title => 'Lower Limb Deformity Analysis';

  @override
  String get viewInfo => 'Standing AP Long-Leg Radiograph';

  @override
  JointCategory get category => JointCategory.other;

  @override
  IconData get icon => Icons.category;

  @override
  String get infoDescription => '''
**Lower Limb Deformity Analysis**

**1. Femoro-Tibial Angle (FTA):** 
Angle between anatomical axes of femur and tibia.

**2. Mechanical Axis Deviation (MAD):** 
Distance from knee center to the mechanical axis (femur head to ankle).

**3. Anatomical Lateral Distal Femoral Angle (aLDFA):** 
Lateral angle between femur anatomical axis and distal femoral joint line.

**4. Anatomical Medial Proximal Tibial Angle (aMPTA):** 
Medial angle between tibia anatomical axis and proximal tibial joint line.

**5. Joint Line Convergence Angle (JLCA):** 
Angle between distal femoral and proximal tibial joint lines.
''';

  @override
  List<TemplateLandmark> get landmarks => [
    TemplateLandmark(id: 'femur_head_center', label: 'Femur Head Center', instruction: 'Mark center of femoral head'),
    TemplateLandmark(id: 'femur_shaft_prox', label: 'Femur Shaft Proximal', instruction: 'Mark center of proximal femur shaft'),
    TemplateLandmark(id: 'femur_shaft_dist', label: 'Femur Shaft Distal', instruction: 'Mark center of distal femur shaft'),
    TemplateLandmark(id: 'femur_condyle_med', label: 'Medial Femoral Condyle', instruction: 'Mark most distal point of medial femoral condyle'),
    TemplateLandmark(id: 'femur_condyle_lat', label: 'Lateral Femoral Condyle', instruction: 'Mark most distal point of lateral femoral condyle'),
    TemplateLandmark(id: 'knee_center', label: 'Knee Center', instruction: 'Mark center of knee joint'),
    TemplateLandmark(id: 'tibia_plateau_med', label: 'Medial Tibial Plateau', instruction: 'Mark medial corner of tibial plateau'),
    TemplateLandmark(id: 'tibia_plateau_lat', label: 'Lateral Tibial Plateau', instruction: 'Mark lateral corner of tibial plateau'),
    TemplateLandmark(id: 'tibia_shaft_prox', label: 'Tibia Shaft Proximal', instruction: 'Mark center of proximal tibia shaft'),
    TemplateLandmark(id: 'tibia_shaft_dist', label: 'Tibia Shaft Distal', instruction: 'Mark center of distal tibia shaft'),
    TemplateLandmark(id: 'ankle_center', label: 'Ankle Center', instruction: 'Mark center of talus/ankle'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (points.length < landmarks.length) return [];

    final p = {for (int i = 0; i < landmarks.length; i++) landmarks[i].id: denormalize(points[i].position, imageRect)};

    final fShaftProx = p['femur_shaft_prox']!;
    final fShaftDist = p['femur_shaft_dist']!;
    final tShaftProx = p['tibia_shaft_prox']!;
    final tShaftDist = p['tibia_shaft_dist']!;

    // 1. FTA (Acute angle / Narrow angle as requested)
    final fta = GeometryUtils.calculateCobbAngle(fShaftProx, fShaftDist, tShaftProx, tShaftDist);

    // 2. MAD
    final head = p['femur_head_center']!;
    final ankle = p['ankle_center']!;
    final knee = p['knee_center']!;
    
    // Projection of knee on mechanical axis
    final proj = GeometryUtils.projectPointToLine(knee, head, ankle);
    double madPx = (knee - proj).distance;
    
    // Directionality (Heuristic: cross product)
    // V = ankle - head. W = knee - head.
    final V = ankle - head;
    final W = knee - head;
    final crossProduct = V.dx * W.dy - V.dy * W.dx;
    
    // In typical AP view (Feet down), if crossProduct > 0, knee is medially deviated for RIGHT leg.
    // This is hard to be 100% correct without side toggle, but we can add "+" or "-" suffix.
    String direction = crossProduct > 0 ? '(M)' : '(L)';
    // MAD (Millimeters)
    double madMm = (pixelsPerMm != null && pixelsPerMm > 0) ? madPx / pixelsPerMm : madPx;

    // 3. aLDFA (Lateral angle)
    final fCondMed = p['femur_condyle_med']!;
    final fCondLat = p['femur_condyle_lat']!;
    final aldfa = GeometryUtils.calculateCobbAngle(fShaftProx, fShaftDist, fCondMed, fCondLat);
    // aLDFA is typically ~81 deg. If it's acute (<90), it's likely the one we want.

    // 4. aMPTA (Medial angle)
    final tPlatMed = p['tibia_plateau_med']!;
    final tPlatLat = p['tibia_plateau_lat']!;
    final ampta = GeometryUtils.calculateCobbAngle(tShaftProx, tShaftDist, tPlatMed, tPlatLat);

    // 5. JLCA
    final jlca = GeometryUtils.calculateCobbAngle(fCondMed, fCondLat, tPlatMed, tPlatLat);

    final unit = pixelsPerMm != null ? 'mm' : 'px';

    return [
      'FTA: ${fta.toStringAsFixed(1)}°',
      'MAD: ${madMm.toStringAsFixed(1)} $unit $direction',
      'aLDFA: ${aldfa.toStringAsFixed(1)}°',
      'aMPTA: ${ampta.toStringAsFixed(1)}°',
      'JLCA: ${jlca.toStringAsFixed(1)}°',
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

    final paintMech = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 1. Femur Anatomical Axis
    if (pMap.containsKey('femur_shaft_prox') && pMap.containsKey('femur_shaft_dist')) {
      final p1 = pMap['femur_shaft_prox']!;
      final p2 = pMap['femur_shaft_dist']!;
      canvas.drawLine(p1, p2, paintMain);
      paintExtendedLine(canvas, p1, p2, imageRect, paintDash);
    }

    // 2. Tibia Anatomical Axis
    if (pMap.containsKey('tibia_shaft_prox') && pMap.containsKey('tibia_shaft_dist')) {
      final p1 = pMap['tibia_shaft_prox']!;
      final p2 = pMap['tibia_shaft_dist']!;
      canvas.drawLine(p1, p2, paintMain);
      paintExtendedLine(canvas, p1, p2, imageRect, paintDash);
    }

    // 3. Mechanical Axis (Femur Head to Ankle)
    if (pMap.containsKey('femur_head_center') && pMap.containsKey('ankle_center')) {
      final p1 = pMap['femur_head_center']!;
      final p2 = pMap['ankle_center']!;
      canvas.drawLine(p1, p2, paintMech);
      
      // Draw deviation line if knee center exists
      if (pMap.containsKey('knee_center')) {
        final knee = pMap['knee_center']!;
        final proj = GeometryUtils.projectPointToLine(knee, p1, p2);
        canvas.drawLine(knee, proj, paintMech..strokeWidth = 2.0);
      }
    }

    // 4. Femoral Distal Joint Line
    if (pMap.containsKey('femur_condyle_med') && pMap.containsKey('femur_condyle_lat')) {
      final p1 = pMap['femur_condyle_med']!;
      final p2 = pMap['femur_condyle_lat']!;
      canvas.drawLine(p1, p2, paintMain);
    }

    // 5. Tibial Proximal Joint Line
    if (pMap.containsKey('tibia_plateau_med') && pMap.containsKey('tibia_plateau_lat')) {
      final p1 = pMap['tibia_plateau_med']!;
      final p2 = pMap['tibia_plateau_lat']!;
      canvas.drawLine(p1, p2, paintMain);
    }
  }
}
