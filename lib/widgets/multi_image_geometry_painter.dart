import 'package:flutter/material.dart';

import '../models/multi_image_session.dart';
import '../templates/multi_image/multi_image_template.dart';

/// Draws a multi-image template's combined construction live over the
/// combined view on the standard measurement screen.
class MultiImageGeometryPainter extends CustomPainter {
  final MultiImageTemplate template;
  final MultiImageSession session;

  /// Where the combined image is laid out on screen.
  final Rect imageRect;

  /// Native size of the combined image (= the base image).
  final Size imageSize;

  /// Current zoom of the viewer, to keep strokes a constant on-screen width.
  final double viewScale;

  MultiImageGeometryPainter({
    required this.template,
    required this.session,
    required this.imageRect,
    required this.imageSize,
    required this.viewScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final kBase = session.mmPerPx(session.baseIndex);
    if (kBase == null || imageSize.width == 0) return;
    final mm = landmarksInMm(
      template,
      [for (final e in session.images) e.points],
      [for (final e in session.images) e.calibrationPointCount],
      [for (var i = 0; i < session.images.length; i++) session.mmPerPx(i)],
    );
    final fit = imageRect.width / imageSize.width;
    canvas.save();
    canvas.clipRect(imageRect);
    canvas.translate(imageRect.left, imageRect.top);
    canvas.scale(fit);
    template.paintCombined(canvas, mm, (p) => p / kBase, 1 / (viewScale * fit));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MultiImageGeometryPainter old) =>
      old.session != session ||
      old.imageRect != imageRect ||
      old.viewScale != viewScale;
}

/// Result lines of a stored multi-image session, as label/value maps for
/// the standard result box and export.
List<Map<String, String>> multiImageResultItems(
  MultiImageTemplate template,
  MultiImageSession session,
) {
  final mm = landmarksInMm(
    template,
    [for (final e in session.images) e.points],
    [for (final e in session.images) e.calibrationPointCount],
    [for (var i = 0; i < session.images.length; i++) session.mmPerPx(i)],
  );
  final needed = [
    for (final step in template.steps) ...step.landmarks.map((l) => l.id),
  ];
  if (!needed.every(mm.containsKey)) return [];
  return [
    for (final r in template.calculate(mm))
      {'label': r.label, 'value': r.value},
  ];
}
