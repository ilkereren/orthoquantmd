import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class FlatfootApTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'flatfoot_ap';

  @override
  String get title => 'Flatfoot';

  @override
  String get viewInfo => 'Standing AP';

  @override
  JointCategory get category => JointCategory.foot;

  @override
  IconData get icon => Icons.personal_injury;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['flatfoot_ap'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'talus_axis_prox', label: 'Talus Axis Prox', instruction: 'Mark Proximal Center of Talus'),
    const TemplateLandmark(id: 'talus_axis_dist', label: 'Talus Axis Dist', instruction: 'Mark Distal Center of Talus'),
    const TemplateLandmark(id: 'm1_axis_base', label: 'M1 Base', instruction: 'Mark Center of M1 Base'),
    const TemplateLandmark(id: 'm1_axis_head', label: 'M1 Head', instruction: 'Mark Center of M1 Head'),
    
    const TemplateLandmark(id: 'talus_art_med', label: 'Talus Articular Med', instruction: 'Mark Medial Edge of Talar Head Articular Surface'),
    const TemplateLandmark(id: 'talus_art_lat', label: 'Talus Articular Lat', instruction: 'Mark Lateral Edge of Talar Head Articular Surface'),
    const TemplateLandmark(id: 'nav_art_med', label: 'Navicular Articular Med', instruction: 'Mark Medial Edge of Navicular Articular Surface'),
    const TemplateLandmark(id: 'nav_art_lat', label: 'Navicular Articular Lat', instruction: 'Mark Lateral Edge of Navicular Articular Surface'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];
    
    // Indices: 
    // 0:TalProx, 1:TalDist, 2:M1Base, 3:M1Head
    // 4:TalArtMed, 5:TalArtLat, 6:NavArtMed, 7:NavArtLat
    
    // TMA: Talus(0-1) vs M1(2-3)
    if (s.length >= 4) {
       final tma = GeometryUtils.calculateCobbAngle(s[0], s[1], s[2], s[3]);
       results.add('Talar-Metatarsal Angle: ${tma.toStringAsFixed(1)}°');
    }
    
    // TN Coverage Angle: TalusArt(4-5) vs NavArt(6-7)
    if (s.length >= 8) {
       final tnca = GeometryUtils.calculateTNCA(s[4], s[5], s[6], s[7]);
       results.add('Talonavicular Coverage Angle: ${tnca.toStringAsFixed(1)}°');
       
       // TN Uncoverage %: TalusLat(5), TalusMed(4), NavMed(6)
       final tnup = GeometryUtils.calculateTNUP(s[5], s[4], s[6]);
       results.add('Talonavicular Uncoverage: ${tnup.toStringAsFixed(1)}%');
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
     
     // TMA lines (extended)
     if (s.length >= 2) paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);
     if (s.length >= 4) paintExtendedLine(canvas, s[2], s[3], imageRect, pLine);
     
     // TNCA lines (segment only)
     if (s.length >= 8) {
         canvas.drawLine(s[4], s[5], pLine);
         canvas.drawLine(s[6], s[7], pLine);
     }
  }
}
