import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class HalluxValgusTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'hallux_valgus';

  @override
  String get title => 'Hallux Valgus';

  @override
  String get viewInfo => 'Standing AP';

  @override
  JointCategory get category => JointCategory.foot;

  @override
  IconData get icon => Icons.do_not_step;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['hallux_valgus'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'm1_head', label: 'M1 Head', instruction: 'Mark Center of Metatarsal 1 Head'),
    const TemplateLandmark(id: 'm1_base', label: 'M1 Base', instruction: 'Mark Center of Metatarsal 1 Base'),
    const TemplateLandmark(id: 'm1_art_med', label: 'M1 Articular Med', instruction: 'Mark Medial Edge of M1 Articular Surface'),
    const TemplateLandmark(id: 'm1_art_lat', label: 'M1 Articular Lat', instruction: 'Mark Lateral Edge of M1 Articular Surface'),
    const TemplateLandmark(id: 'm2_head', label: 'M2 Head', instruction: 'Mark Center of Metatarsal 2 Head'),
    const TemplateLandmark(id: 'm2_base', label: 'M2 Base', instruction: 'Mark Center of Metatarsal 2 Base'),
    const TemplateLandmark(id: 'p1_head', label: 'P1 Head', instruction: 'Mark Center of Proximal Phalanx Head'),
    const TemplateLandmark(id: 'p1_base', label: 'P1 Base', instruction: 'Mark Center of Proximal Phalanx Base'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    final results = <String>[];

    // Helper to find point by label (partial match or exact)
    Offset? getPoint(String labelPart) {
       try {
         final p = points.firstWhere((pt) => pt.label.contains(labelPart));
         return denormalize(p.position, imageRect);
       } catch (_) {
         return null;
       }
    }

    final m1Head = getPoint('M1 Head');
    final m1Base = getPoint('M1 Base');
    final p1Head = getPoint('P1 Head');
    final p1Base = getPoint('P1 Base');
    
    // HVA: M1 Axis (Head-Base) vs P1 Axis (Head-Base)
    if (m1Head != null && m1Base != null && p1Head != null && p1Base != null) {
       final hva = GeometryUtils.calculateCobbAngle(m1Head, m1Base, p1Head, p1Base);
       results.add('Hallux Valgus Angle: ${hva.toStringAsFixed(1)}°');
    }
    
    final m2Head = getPoint('M2 Head');
    final m2Base = getPoint('M2 Base');
    
    // IMA: M1 Axis vs M2 Axis
    if (m1Head != null && m1Base != null && m2Head != null && m2Base != null) {
       final ima = GeometryUtils.calculateCobbAngle(m1Head, m1Base, m2Head, m2Base);
       results.add('Intermetatarsal Angle: ${ima.toStringAsFixed(1)}°');
    }
    
    final m1ArtMed = getPoint('M1 Articular Med');
    final m1ArtLat = getPoint('M1 Articular Lat');
 
    // DMAA: M1 Axis vs M1 Articular Surface
    if (m1Head != null && m1Base != null && m1ArtMed != null && m1ArtLat != null) {
       final dmaa = GeometryUtils.calculateCobbAngle(m1Head, m1Base, m1ArtMed, m1ArtLat);
       results.add('Distal Metatarsal Articular Angle: ${dmaa.toStringAsFixed(1)}°');
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
     
     // 0-1 M1 Axis
     if (s.length >= 2) paintExtendedLine(canvas, s[0], s[1], imageRect, pLine);
     
     // 2-3 M1 Articular
     if (s.length >= 4) canvas.drawLine(s[2], s[3], pLine); // Usually short line
     
     // 4-5 M2 Axis
     if (s.length >= 6) paintExtendedLine(canvas, s[4], s[5], imageRect, pLine);
     
     // 6-7 P1 Axis
     if (s.length >= 8) paintExtendedLine(canvas, s[6], s[7], imageRect, pLine);
  }
}
