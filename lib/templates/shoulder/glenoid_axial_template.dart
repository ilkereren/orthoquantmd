import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/models/measurement_model.dart'; // ReferencePoint
import 'package:ortho_quant_md/data/template_descriptions.dart'; // TemplateDescriptions
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class GlenoidAxialTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'glenoid_version';

  @override
  String get title => 'Glenoid Analysis';

  @override
  String get viewInfo => 'Axial CT';

  @override
  JointCategory get category => JointCategory.shoulder;

  @override
  IconData get icon => Icons.api;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['glenoid_version'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'scapula_medial', label: 'Scapula Medial Border (A)', instruction: 'Place point on the medial border of the scapula.'),
    const TemplateLandmark(id: 'glenoid_anterior', label: 'Glenoid Anterior (B)', instruction: 'Place point on the anterior margin of the glenoid.'),
    const TemplateLandmark(id: 'glenoid_posterior', label: 'Glenoid Posterior (C)', instruction: 'Place point on the posterior margin of the glenoid.'),
    const TemplateLandmark(id: 'humeral_anterior', label: 'Humeral Head Anterior (D)', instruction: 'Place point on the anterior margin of the humeral head.'),
    const TemplateLandmark(id: 'humeral_posterior', label: 'Humeral Head Posterior (E)', instruction: 'Place point on the posterior margin of the humeral head.'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
    
    if (screenPoints.length < 3) return [];
    
    final result = GeometryUtils.calculateGlenoidVersion(screenPoints);
    
    final list = <String>[];
    list.add('Retroversion: ${result['retroversion']!.toStringAsFixed(1)}°');
    
    final medVal = result['medialization']!;
    if (medVal != 0) {
        if (pixelsPerMm != null && pixelsPerMm > 0) {
            final medMm = medVal / pixelsPerMm;
            list.add('Medialization: ${medMm.toStringAsFixed(1)} mm');
        } else {
            list.add('Medialization: ${medVal.toStringAsFixed(1)} px');
        }
    }
    
    if (screenPoints.length >= 5) {
        list.add('Subluxation: ${result['subluxation']!.toStringAsFixed(1)}%');
    }
    
    return list;
  }

  @override
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect) {
     if (points.isEmpty || imageRect.isEmpty) return;
     
     final screenPoints = points.map((p) => denormalize(p.position, imageRect)).toList();
     
     final pLine = paint..strokeWidth = 2.0 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent;
     final pPoint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
     
    for (var pt in screenPoints) {
       canvas.drawCircle(pt, 4.0/scale, pPoint);
    }

     if (screenPoints.length >= 3) {
         final A = screenPoints[0];
         final B = screenPoints[1];
         final C = screenPoints[2]; // Posterior
         
         final M = (B + C) / 2;
         
         final pDashed = Paint()..strokeWidth = 1.0 / scale..style = PaintingStyle.stroke..color = Colors.cyanAccent.withValues(alpha: 0.6);

         // Draw Scapular Axis A-M
         canvas.drawLine(A, M, pLine);
         
         // 1. Perpendicular to Axis AM
         final vAM = M - A;
         if (vAM.distance > 0) {
             final nAM = vAM / vAM.distance;
             final perp = Offset(-nAM.dy, nAM.dx);
             
             // Perpendicular at M
             paintDashedLine(canvas, M - perp * 30, M + perp * 30, pDashed);
             
             // Perpendicular at C (Posterior)
             paintDashedLine(canvas, C - perp * 30, C + perp * 30, pDashed);
             
             // Dimension Line (Medialization distance along axis)
             // Project C onto Scapular Axis AM
             final tC = ((C.dx - A.dx) * nAM.dx + (C.dy - A.dy) * nAM.dy);
             final projC = A + nAM * tC;
             
             // Line between M and its projection of C along axis to show the "gap"
             paintDashedLine(canvas, M, projC, Paint()..strokeWidth = 1.5/scale..color = Colors.yellowAccent..style = PaintingStyle.stroke);
         }

         // Draw Glenoid Line B-C
         canvas.drawLine(B, C, pLine);
     }
  }
}
