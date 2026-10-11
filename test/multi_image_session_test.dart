import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/models/multi_image_session.dart';
import 'package:ortho_quant_md/templates/multi_image/tt_tg_template.dart';
import 'package:ortho_quant_md/widgets/multi_image_geometry_painter.dart';

Offset knee(double x, double y, {double deg = 8, double zoom = 1}) {
  final c = math.cos(deg * math.pi / 180), s = math.sin(deg * math.pi / 180);
  return Offset(450 + (x * c - y * s) * zoom, 400 + (x * s + y * c) * zoom);
}

void main() {
  // Image 2 photographed closer (1.25x): its own calibration absorbs it.
  final session = MultiImageSession(
    templateId: 'tt_tg_distance',
    baseIndex: 0,
    overlayOpacity: 0.5,
    images: [
      MultiImageEntry(
        path: '/docs/mi_1_0.png',
        calibrationMm: 50,
        calibrationPointCount: 2,
        points: [
          const Offset(60, 740),
          const Offset(260, 740),
          knee(-100, 120),
          knee(100, 120),
          knee(0, -60),
        ],
      ),
      MultiImageEntry(
        path: '/docs/mi_1_1.png',
        calibrationMm: 50,
        calibrationPointCount: 2,
        points: [
          const Offset(60, 740) * 1.25,
          const Offset(260, 740) * 1.25,
          knee(80, -108) * 1.25,
        ],
      ),
    ],
  );

  test('session survives a record JSON round trip', () {
    final record = MeasurementRecord(
      id: 'r1',
      timestamp: DateTime(2026, 10, 11),
      imagePath: '/docs/mi_1_combined.png',
      measurements: [],
      multiImage: session,
    );
    final back = MeasurementRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );
    final s = back.multiImage!;
    expect(s.templateId, 'tt_tg_distance');
    expect(s.images, hasLength(2));
    expect(s.images[1].points.last, session.images[1].points.last);
    expect(s.mmPerPx(0), closeTo(0.25, 1e-9));
    expect(s.mmPerPx(1), closeTo(0.2, 1e-9));
  });

  test('records without a session still load', () {
    final r = MeasurementRecord.fromJson({
      'id': 'r0',
      'timestamp': DateTime(2026).toIso8601String(),
      'imagePath': '/x.png',
      'measurements': [],
    });
    expect(r.multiImage, isNull);
  });

  test('result items are recomputed from the stored session', () {
    final items = multiImageResultItems(TtTgTemplate(), session);
    expect(items.first, {'label': 'TT-TG', 'value': '20.0 mm'});
    expect(items[1]['value'], 'Lateral');
  });
}
