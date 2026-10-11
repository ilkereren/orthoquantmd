import 'dart:ui';

/// One image of a multi-image measurement, as stored in a record.
class MultiImageEntry {
  /// Persistent copy of the image in the app's documents directory.
  final String path;

  /// Placed points in native image pixels: the first `calibrationPointCount`
  /// are the calibration line, the rest follow the template's landmarks.
  final List<Offset> points;

  /// Real length of the calibration line in mm (null when the image
  /// inherits calibration from an earlier image).
  final double? calibrationMm;

  /// 2 when this image carries its own calibration line, 0 otherwise.
  final int calibrationPointCount;

  const MultiImageEntry({
    required this.path,
    required this.points,
    required this.calibrationMm,
    required this.calibrationPointCount,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'points': [
      for (final p in points) [p.dx, p.dy],
    ],
    'calibrationMm': calibrationMm,
    'calibrationPointCount': calibrationPointCount,
  };

  factory MultiImageEntry.fromJson(Map<String, dynamic> json) =>
      MultiImageEntry(
        path: json['path'] as String,
        points: [
          for (final p in json['points'] as List)
            Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        calibrationMm: (json['calibrationMm'] as num?)?.toDouble(),
        calibrationPointCount: json['calibrationPointCount'] as int? ?? 2,
      );

  /// mm per native pixel from this image's own calibration line.
  double? get ownMmPerPx {
    if (calibrationPointCount < 2 ||
        points.length < 2 ||
        calibrationMm == null ||
        calibrationMm! <= 0) {
      return null;
    }
    final px = (points[1] - points[0]).distance;
    return px == 0 ? null : calibrationMm! / px;
  }
}

/// Everything needed to reopen and redraw a multi-image measurement: the
/// source images with their points, and how the combined view is shown.
class MultiImageSession {
  final String templateId;
  final List<MultiImageEntry> images;

  /// Image the combined view is drawn on.
  final int baseIndex;

  /// Opacity of the other images over the base in the combined view.
  final double overlayOpacity;

  const MultiImageSession({
    required this.templateId,
    required this.images,
    required this.baseIndex,
    required this.overlayOpacity,
  });

  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'images': images.map((e) => e.toJson()).toList(),
    'baseIndex': baseIndex,
    'overlayOpacity': overlayOpacity,
  };

  factory MultiImageSession.fromJson(Map<String, dynamic> json) =>
      MultiImageSession(
        templateId: json['templateId'] as String,
        images: [
          for (final e in json['images'] as List)
            MultiImageEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
        baseIndex: json['baseIndex'] as int? ?? 0,
        overlayOpacity: (json['overlayOpacity'] as num?)?.toDouble() ?? 0.5,
      );

  /// mm per pixel of image [i]; images without their own calibration use the
  /// nearest earlier calibrated image.
  double? mmPerPx(int i) {
    for (var j = i; j >= 0; j--) {
      if (images[j].calibrationPointCount >= 2) return images[j].ownMmPerPx;
    }
    return null;
  }
}
