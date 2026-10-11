import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/models/multi_image_session.dart';
import 'package:ortho_quant_md/screens/multi_image_template_screen.dart';
import 'package:ortho_quant_md/templates/multi_image/femoral_version_template.dart';
import 'package:ortho_quant_md/widgets/multi_image_geometry_painter.dart';

/// Points of one femur in image px, anterior at the top. The condylar line
/// is tilted by [tilt]°; the neck axis points medially and turned
/// anteriorly by [version]° relative to it. [right] mirrors the femur.
Map<String, Offset> femur({
  required double version,
  double tilt = 7,
  bool right = true,
}) {
  final t = tilt * math.pi / 180, v = version * math.pi / 180;
  final m = right ? 1.0 : -1.0;
  // Medial along +x for a right femur shown on the image's left.
  final u = Offset(math.cos(t) * m, math.sin(t) * m);
  final ant = Offset(u.dy * m, -u.dx * m); // points image-up
  const neck = Offset(400, 300);
  final dir = u * math.cos(v) + ant * math.sin(v);
  return {
    'neck': neck,
    'head': neck + dir * 60,
    'lpc': const Offset(400, 500) - u * 90,
    'mpc': const Offset(400, 500) + u * 90,
  };
}

void main() {
  final t = FemoralVersionTemplate();

  test('reads anteversion and retroversion on either side', () {
    for (final right in [true, false]) {
      expect(
        t.versionDegrees(femur(version: 15, right: right)),
        closeTo(15, 1e-9),
      );
      expect(
        t.versionDegrees(femur(version: -8, right: right)),
        closeTo(-8, 1e-9),
      );
    }
    final lines = t.calculate(femur(version: 15));
    expect(lines.first.label, 'Anteversion');
    expect(lines.first.value, '15.0°');
    expect(lines[1].value, 'Normal');
    expect(t.calculate(femur(version: -8)).first.label, 'Retroversion');
    expect(t.calculate(femur(version: 28))[1].value, 'Increased');
    expect(t.calculate(femur(version: 5))[1].value, 'Decreased');
  });

  test('needs no calibration and recomputes from a stored session', () {
    expect(t.usesCalibration, isFalse);
    final f = femur(version: 22);
    final session = MultiImageSession(
      templateId: t.id,
      baseIndex: 0,
      overlayOpacity: 0.5,
      screenAspect: 16 / 10,
      images: [
        MultiImageEntry(
          path: '/docs/fv_0.png',
          points: [f['head']!, f['neck']!],
          calibrationMm: null,
          calibrationPointCount: 0,
        ),
        MultiImageEntry(
          path: '/docs/fv_1.png',
          points: [f['mpc']!, f['lpc']!],
          calibrationMm: null,
          calibrationPointCount: 0,
        ),
      ],
    );
    final items = multiImageResultItems(t, session);
    expect(items.first, {'label': 'Anteversion', 'value': '22.0°'});
    expect(items[1]['value'], 'Increased');
  });

  testWidgets('flow asks for no calibration', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: MultiImageTemplateScreen(template: t)),
    );
    await tester.pumpAndSettle();
    // Angle only: the short rotation warning, not the monitor guide.
    expect(t.alignToMonitor, isFalse);
    expect(find.text('Keep both images upright'), findsOneWidget);
    expect(find.text('Before you take the photos'), findsNothing);
    expect(find.text('Take Photo'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // close the guide
    await tester.pumpAndSettle();

    Finder canvas() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_StepPainter',
    );
    Future<void> load() async {
      await tester.tap(find.text('Demo image'));
      for (var i = 0; i < 20 && canvas().evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> tapPx(Offset px) async {
      final rect = tester.getRect(canvas());
      await tester.tapAt(rect.topLeft + px * (rect.width / 900));
      await tester.pumpAndSettle();
    }

    final f = femur(version: 15);
    await load();
    expect(find.text('Calibrate'), findsNothing);
    expect(find.textContaining('Calibration from'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    await tapPx(f['head']!);
    await tapPx(f['neck']!);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await load();
    expect(find.text('Calibrate'), findsNothing);
    await tapPx(f['mpc']!);
    await tapPx(f['lpc']!);
    await tester.tap(find.text('Result').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('15.0°', findRichText: true), findsWidgets);
    expect(find.textContaining('Normal', findRichText: true), findsOneWidget);
  });
}
