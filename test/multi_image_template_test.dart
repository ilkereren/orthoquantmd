import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/screens/multi_image_template_screen.dart';
import 'package:ortho_quant_md/templates/multi_image/tt_tg_template.dart';

/// Demo knee geometry (see _DemoImages): local point → native image px.
Offset demoPx(double x, double y) {
  const deg = 8.0;
  final c = math.cos(deg * math.pi / 180), s = math.sin(deg * math.pi / 180);
  return Offset(450 + x * c - y * s, 400 + x * s + y * c);
}

Finder stepCanvas() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_StepPainter',
);

Future<void> tapImagePx(WidgetTester tester, Offset px) async {
  final rect = tester.getRect(stepCanvas());
  final scale = rect.width / 900;
  await tester.tapAt(rect.topLeft + px * scale);
  await tester.pumpAndSettle();
}

Future<void> doStep(
  WidgetTester tester,
  List<Offset> landmarks, {
  bool calibrate = true,
}) async {
  await tester.tap(find.text('Demo image'));
  for (var i = 0; i < 20 && stepCanvas().evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();

  if (calibrate) {
    await tapImagePx(tester, const Offset(60, 740));
    await tapImagePx(tester, const Offset(260, 740));
    // The standard "Calibrate Scale" dialog opens by itself.
    expect(find.text('Calibrate Scale'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  } else {
    // Calibration is inherited: no field, the first prompt is a landmark.
    expect(find.text('Calibrate'), findsNothing);
    expect(find.textContaining('Calibration from Image 1'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
  }
  for (final p in landmarks) {
    await tapImagePx(tester, p);
  }
}

void main() {
  testWidgets('TT-TG multi-image flow yields the known 20.0 mm', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: MultiImageTemplateScreen(template: TtTgTemplate())),
    );
    await tester.pumpAndSettle();

    // Result tab is locked until both images are done.
    expect(find.byIcon(Icons.lock), findsNWidgets(2));

    await doStep(tester, [demoPx(-100, 120), demoPx(100, 120), demoPx(0, -60)]);
    expect(find.text('Image 1 complete. Tap Next.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Image 2 is calibrated on its own; the dialog suggests Image 1's mm.
    await doStep(tester, [demoPx(80, -108)]);
    await tester.tap(find.text('Result').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('20.0 mm', findRichText: true), findsOneWidget);
    expect(find.text('Lateral'), findsOneWidget);

    // Overlay control and DONE are available on the result tab.
    expect(find.text('Overlay'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);

    // Go back to image 2, drag TT 40 px (= 10 mm) medially along the knee's
    // mediolateral axis; the result must follow without re-entering anything.
    await tester.tap(find.text('Image 2'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(stepCanvas());
    final scale = rect.width / 900;
    final from = rect.topLeft + demoPx(80, -108) * scale;
    final to = rect.topLeft + demoPx(40, -108) * scale;
    await tester.timedDragFrom(
      from,
      to - from,
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Result').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('10.0 mm', findRichText: true), findsOneWidget);
    expect(find.textContaining('Normal', findRichText: true), findsOneWidget);
  });
}
