import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart' hide Icons, TemplateDescriptions;
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class PatellaIndicesTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'patella_indices';

  @override
  String get title => 'Patella Indices';

  @override
  String get viewInfo => 'True Lateral';

  @override
  JointCategory get category => JointCategory.knee;

  @override
  IconData get icon => Icons.directions_walk;

  @override
  String get infoDescription => TemplateDescriptions.infoDescriptions['patella_indices'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(id: 'patella_sup', label: 'Patella Superior', instruction: 'Mark Superior Pole of Patella (Articular)'),
    const TemplateLandmark(id: 'patella_inf', label: 'Patella Inferior', instruction: 'Mark Inferior Pole of Patella (Articular)'),
    const TemplateLandmark(id: 'tibial_tuberosity', label: 'Tibial Tuberosity', instruction: 'Mark Tibial Tuberosity'),
    const TemplateLandmark(id: 'tibial_plat_post', label: 'Tibial Plat Post', instruction: 'Mark Posterior Edge of Tibial Plateau'),
    const TemplateLandmark(id: 'tibial_plat_ant', label: 'Tibial Plat Ant', instruction: 'Mark Anterior Edge of Tibial Plateau'),
  ];

  @override
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm}) {
    if (imageRect.isEmpty) return [];
    
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];
    
    // Indices: 0:PS, 1:PI, 2:Tub, 3:PlatPost, 4:PlatAnt
    
    // MIS: PatSup(0), PatInf(1), Tub(2)
    if (s.length >= 3) {
       final mis = GeometryUtils.calculateModifiedInsallSalvati(s[0], s[1], s[2]);
       results.add('Modified Insall-Salvati Index: ${mis.toStringAsFixed(2)}');
    }
    
    // BP: PatSup(0), PatInf(1), PlatPost(3), PlatAnt(4)
    if (s.length >= 5) {
       final bp = GeometryUtils.calculateBlackburnePeel(s[0], s[1], s[3], s[4]);
       results.add('Blackburne-Peel Index: ${bp.toStringAsFixed(2)}');
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
     
     // MIS Visual: Inf->Tub
     if (s.length >= 3) {
         canvas.drawLine(s[1], s[2], pLine);
         // Also Articular Surface Sup->Inf usually
         canvas.drawLine(s[0], s[1], pLine..color=Colors.yellow);
     }
     
     // BP Visual: Plateau Line (extended) + Perp from Inf
     if (s.length >= 5) {
         pLine.color = Colors.cyanAccent;
         // Plateau Line
         paintExtendedLine(canvas, s[3], s[4], imageRect, pLine);
         
         // Helper to find proj point for visual perp
         final proj = GeometryUtils.projectPointToLine(s[1], s[3], s[4]);
         canvas.drawLine(s[1], proj, pLine..style=PaintingStyle.stroke..color=Colors.redAccent); // Perp height
     }
  }
}
