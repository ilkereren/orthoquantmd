import 'package:flutter/material.dart';
import '../../models/template_model.dart';
import '../../models/measurement_model.dart';
import '../../widgets/measurement_boxes.dart'; // TemplateResultBox
import '../../utils/geometry.dart';

/// Abstract base class for all Measurement Templates.
/// Encapsulates landmarks, calculations, and painting logic.
abstract class MeasurementTemplateBase {
  /// Unique Identifier
  String get id;

  /// User-facing Title
  String get title;

  /// Detailed View Information (e.g. "Standing AP", "Lateral")
  /// Displayed as a subtitle in the menu.
  String get viewInfo;

  /// Joint Category
  JointCategory get category;

  /// Menu Icon
  IconData get icon;

  /// Detailed Description (Markdown supported)
  String get infoDescription;

  /// List of landmarks to be placed by the user.
  /// The order here defines the input sequence.
  List<TemplateLandmark> get landmarks;

  /// Optional: Custom painting logic for this template.
  /// [canvas]: The canvas to draw on.
  /// [points]: All points placed so far (normalized).
  /// [scale]: Current view scale factor.
  /// [paint]: Base paint style (color, stroke width).
  /// [imageRect]: The rect of the image on screen.
  void paint(Canvas canvas, List<ReferencePoint> points, double scale, Paint paint, Rect imageRect);

  /// Performs calculations based on the placed points.
  /// Returns a list of calculation results to be displayed.
  /// Each result can be a formatted string or a structured object.
  List<String> calculate(List<ReferencePoint> points, Rect imageRect, {double? pixelsPerMm});

  /// Custom Result Box Builder
  /// Standardized logic for displaying results. Templates can override this if needed.
  Widget buildResultBox(BuildContext context, List<String> results, VoidCallback onClose) {
      // Default Parsing: Expects "Label: Value" string format
      final items = results.map((r) {
          final parts = r.split(': ');
          if (parts.length >= 2) {
              return {'label': parts[0], 'value': parts.sublist(1).join(': ')};
          }
          return {'label': r, 'value': ''};
      }).toList();

      return TemplateResultBox(
          title: title,
          items: items,
          onClose: onClose,
      );
  }
  
  /// Helper to convert normalized points to screen coordinates
  Offset denormalize(Offset p, Rect imageRect) {
     if (imageRect.isEmpty) return p;
     return Offset(
       imageRect.left + p.dx * imageRect.width, 
       imageRect.top + p.dy * imageRect.height
     );
  }

  /// Draws a dashed line between two points.
  void paintDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashWidth = 10.0, double dashSpace = 5.0}) {
    var max = (p2 - p1).distance;
    if (max == 0) return;
    final normalized = (p2 - p1) / max;
    
    double distance = 0.0;
    while (distance < max) {
      final lineStart = p1 + normalized * distance;
      final lineEnd = p1 + normalized * (distance + dashWidth > max ? max : distance + dashWidth);
      canvas.drawLine(lineStart, lineEnd, paint);
      distance += dashWidth + dashSpace;
    }
  }

  /// Draws a line between p1 and p2, extending it infinitely with dashed lines.
  void paintExtendedLine(Canvas canvas, Offset p1, Offset p2, Rect imageRect, Paint paint, {bool isDashed = false}) {
    // 1. Core segment
    if (isDashed) {
      paintDashedLine(canvas, p1, p2, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
    }

    // 2. Extensions
    final infPoints = GeometryUtils.getInfiniteLinePoints(p1, p2, imageRect);
    if (infPoints != null && infPoints.length >= 2) {
      final v = p2 - p1;
      if (v.distance > 0) {
        for (final b in infPoints) {
          // Check if boundary point b is "behind" p1
          final vP1B = b - p1;
          final dotP1 = vP1B.dx * v.dx + vP1B.dy * v.dy;
          if (dotP1 < -0.01) {
            paintDashedLine(canvas, p1, b, paint);
            continue;
          }

          // Check if boundary point b is "ahead" of p2
          final vP2B = b - p2;
          final dotP2 = vP2B.dx * v.dx + vP2B.dy * v.dy;
          if (dotP2 > 0.01) {
            paintDashedLine(canvas, p2, b, paint);
          }
        }
      }
    }
  }
}
