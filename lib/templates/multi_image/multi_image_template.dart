import 'package:flutter/material.dart';

import 'femoral_version_template.dart';
import 'tt_tg_template.dart';

/// Name of the menu that groups measurements spanning several images.
const String multiImageMenuTitle = 'Multi-Image';
const String multiImageMenuSubtitle = 'Measurements across two or more images';

/// All multi-image templates, in menu order.
final List<MultiImageTemplate> multiImageTemplates = [
  TtTgTemplate(),
  FemoralVersionTemplate(),
];

class LandmarkSpec {
  final String id;
  final String label;
  final String instruction;

  /// A ring fitted to a round outline (e.g. the femoral head): placed with
  /// one tap, then moved by its centre and resized by a handle on its edge.
  /// Its centre is the landmark. Stored as two points: centre, edge handle.
  final bool ring;

  const LandmarkSpec(
    this.id,
    this.label,
    this.instruction, {
    this.ring = false,
  });

  int get pointCount => ring ? 2 : 1;
}

class ImageStepSpec {
  final String title;
  final String loadPrompt;
  final List<LandmarkSpec> landmarks;

  /// One line for the photo guide: which slice, and what is marked on it.
  final String summary;

  /// False when the image shares the pixel spacing of the previous
  /// calibrated image (e.g. slices of the same CT series at the same zoom),
  /// so calibration is inherited instead of asked again.
  final bool calibrate;

  const ImageStepSpec({
    required this.title,
    required this.loadPrompt,
    required this.landmarks,
    this.summary = '',
    this.calibrate = true,
  });

  /// Points placed for the landmarks (rings take two).
  int get landmarkPointCount =>
      landmarks.fold(0, (sum, l) => sum + l.pointCount);

  /// The landmark that point [k] (counted after calibration) belongs to,
  /// and whether it is a ring's edge handle rather than the landmark itself.
  ({int landmark, bool ringEdge}) landmarkAt(int k) {
    var start = 0;
    for (var j = 0; j < landmarks.length; j++) {
      final n = landmarks[j].pointCount;
      if (k < start + n) return (landmark: j, ringEdge: k > start);
      start += n;
    }
    return (landmark: landmarks.length, ringEdge: false);
  }
}

class ResultLine {
  final String label;
  final String value;
  final Color? color;
  const ResultLine(this.label, this.value, {this.color});
}

/// Maps a point in the common millimetre plane to pixels of the image
/// currently being displayed.
typedef MmToPx = Offset Function(Offset mm);

/// Converts every placed landmark to the common millimetre plane.
///
/// [points] holds, per image, the placed points in native pixels (the first
/// [calibrationPointCounts] of them are the calibration line). [mmPerPx] is
/// the scale of each image. Images are related by scale only: they are
/// assumed to share framing (same viewer zoom/pan, photographed alike).
Map<String, Offset> landmarksInMm(
  MultiImageTemplate template,
  List<List<Offset>> points,
  List<int> calibrationPointCounts,
  List<double?> mmPerPx,
) {
  final out = <String, Offset>{};
  for (var i = 0; i < template.steps.length && i < points.length; i++) {
    final k = mmPerPx[i];
    if (k == null) continue;
    var idx = calibrationPointCounts[i];
    for (final spec in template.steps[i].landmarks) {
      // A ring's landmark is its centre, the first of its two points.
      if (idx < points[i].length) out[spec.id] = points[i][idx] * k;
      idx += spec.pointCount;
    }
  }
  return out;
}

MultiImageTemplate? multiImageTemplateById(String id) {
  for (final t in multiImageTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

/// A template whose landmarks are placed on several images.
///
/// Every image keeps its own native pixel space; images are never rescaled
/// to fit each other. Landmarks are converted to millimetres with the
/// calibration of their image and related in one common plane.
abstract class MultiImageTemplate {
  String get id;
  String get title;
  String get viewInfo;
  IconData get icon;
  List<ImageStepSpec> get steps;

  /// False for angle-only templates, which skip calibration entirely.
  bool get usesCalibration => steps.any((s) => s.calibrate);

  /// [mm] holds every landmark of every step, keyed by landmark id, in the
  /// common millimetre plane.
  List<ResultLine> calculate(Map<String, Offset> mm);

  /// Draws geometry of steps other than the one being edited, as guidance.
  void paintGhost(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double strokeScale,
  );

  /// Draws the final combined construction.
  void paintCombined(
    Canvas canvas,
    Map<String, Offset> mm,
    MmToPx toPx,
    double strokeScale,
  );
}
