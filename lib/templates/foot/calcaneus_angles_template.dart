import 'package:flutter/material.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/data/template_descriptions.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

class CalcaneusAnglesTemplate extends MeasurementTemplateBase {
  @override
  String get id => 'calcaneus_angles';

  @override
  String get title => 'Calcaneus – Böhler & Gissane';

  @override
  String get viewInfo => 'Lateral Ankle / Calcaneus';

  @override
  JointCategory get category => JointCategory.foot;

  @override
  IconData get icon => Icons.change_history;

  @override
  String get infoDescription =>
      TemplateDescriptions.infoDescriptions['calcaneus_angles'] ?? '';

  @override
  List<TemplateLandmark> get landmarks => [
    const TemplateLandmark(
      id: 'calc_tuber_sup',
      label: 'Tuberosity Superior',
      instruction:
          'Mark most superior point of the posterior calcaneal tuberosity',
    ),
    const TemplateLandmark(
      id: 'calc_post_facet',
      label: 'Posterior Facet Apex',
      instruction: 'Mark highest point of the posterior subtalar facet',
    ),
    const TemplateLandmark(
      id: 'calc_ant_process',
      label: 'Anterior Process Apex',
      instruction: 'Mark highest point of the anterior process',
    ),
    const TemplateLandmark(
      id: 'calc_gissane_apex',
      label: 'Critical Angle Apex',
      instruction:
          'Mark apex of the critical angle (junction of posterior facet and sulcus calcanei)',
    ),
  ];

  /// Böhler angle with sign: negative when the posterior facet apex lies
  /// below the tuberosity–anterior process line (image assumed upright).
  static double bohlerAngle(Offset tuber, Offset facet, Offset anterior) {
    final magnitude =
        180 - GeometryUtils.calculateAngle(tuber, facet, anterior);
    final base = anterior - tuber;
    var up = Offset(-base.dy, base.dx);
    if (up.dy > 0) up = -up;
    final toFacet = facet - tuber;
    final side = toFacet.dx * up.dx + toFacet.dy * up.dy;
    return side >= 0 ? magnitude : -magnitude;
  }

  @override
  List<String> calculate(
    List<ReferencePoint> points,
    Rect imageRect, {
    double? pixelsPerMm,
  }) {
    if (imageRect.isEmpty) return [];
    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final results = <String>[];

    // Indices: 0:Tuber, 1:PostFacet, 2:AntProcess, 3:GissaneApex
    if (s.length >= 3) {
      final bohler = bohlerAngle(s[0], s[1], s[2]);
      results.add("Böhler's Angle: ${bohler.toStringAsFixed(1)}°");
    }

    if (s.length >= 4) {
      final gissane = GeometryUtils.calculateAngle(s[1], s[3], s[2]);
      results.add("Gissane's Angle: ${gissane.toStringAsFixed(1)}°");
    }

    return results;
  }

  @override
  void paint(
    Canvas canvas,
    List<ReferencePoint> points,
    double scale,
    Paint paint,
    Rect imageRect,
  ) {
    if (points.isEmpty || imageRect.isEmpty) return;

    final s = points.map((p) => denormalize(p.position, imageRect)).toList();
    final pLine = paint
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.cyanAccent;
    final pGissane = Paint()
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..color = Colors.yellowAccent;
    final pPoint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (var pt in s) {
      canvas.drawCircle(pt, 4.0 / scale, pPoint);
    }

    // Böhler: Tuber -> Facet, Facet -> Anterior process
    if (s.length >= 2) canvas.drawLine(s[0], s[1], pLine);
    if (s.length >= 3) {
      canvas.drawLine(s[1], s[2], pLine);
      // Reference: Tuber -> Anterior process baseline
      final pRef = Paint()
        ..strokeWidth = 1.0 / scale
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.6);
      paintDashedLine(canvas, s[0], s[2], pRef);
    }

    // Gissane: Apex -> Facet, Apex -> Anterior process
    if (s.length >= 4) {
      canvas.drawLine(s[3], s[1], pGissane);
      canvas.drawLine(s[3], s[2], pGissane);
    }
  }
}
