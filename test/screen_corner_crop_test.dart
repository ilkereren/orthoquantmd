import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/screens/screen_corner_crop_screen.dart';
import 'package:ortho_quant_md/utils/homography.dart';

const photoW = 1200, photoH = 900;

/// Pinhole photo of a 520 × 325 mm (16:10) screen, camera turned by
/// [yaw]/[pitch]; screen point given in screen units (0..1, 0..1).
Offset photoOf(Offset unit, {double yaw = 18, double pitch = -10}) {
  final mm = Offset((unit.dx - 0.5) * 520, (unit.dy - 0.5) * 325);
  final cy = math.cos(yaw * math.pi / 180), sy = math.sin(yaw * math.pi / 180);
  final cp = math.cos(pitch * math.pi / 180);
  final sp = math.sin(pitch * math.pi / 180);
  final x = cy * mm.dx, z0 = -sy * mm.dx;
  final y = cp * mm.dy - sp * z0, z = sp * mm.dy + cp * z0 + 720;
  return Offset(photoW / 2 + 1150 * x / z, photoH / 2 + 1150 * y / z);
}

const unitCorners = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

/// Grey desk, white screen, red dot at the screen centre and a blue dot at
/// one quarter across and down.
Future<ui.Image> monitorPhoto() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    Rect.fromLTWH(0, 0, photoW.toDouble(), photoH.toDouble()),
    Paint()..color = const Color(0xFF404040),
  );
  c.drawPath(
    Path()..addPolygon([for (final u in unitCorners) photoOf(u)], true),
    Paint()..color = Colors.white,
  );
  c.drawCircle(
    photoOf(const Offset(0.5, 0.5)),
    12,
    Paint()..color = const Color(0xFFFF0000),
  );
  c.drawCircle(
    photoOf(const Offset(0.25, 0.25)),
    12,
    Paint()..color = const Color(0xFF0000FF),
  );
  return rec.endRecording().toImage(photoW, photoH);
}

Future<Color> pixel(ui.Image img, Offset p) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (p.dy.round() * img.width + p.dx.round()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  test('straightens a tilted photo onto the screen plane', () async {
    final photo = await monitorPhoto();
    final corners = [for (final u in unitCorners) photoOf(u)];
    final aspect = snapScreenShape(
      estimateScreenAspect(corners, const Offset(photoW / 2, photoH / 2)),
    );
    expect(aspect, 16 / 10);

    final out = await straightenScreenPhoto(photo, corners, aspect);
    expect(out.width, 2560);
    expect(out.height, alignedScreenHeight);
    expect((await pixel(out, const Offset(1280, 800))).r, greaterThan(0.8));
    expect((await pixel(out, const Offset(1280, 800))).b, lessThan(0.2));
    expect((await pixel(out, const Offset(640, 400))).b, greaterThan(0.8));
    expect((await pixel(out, const Offset(1900, 1300))).g, greaterThan(0.8));
  });

  test('crossed corners are rejected', () {
    expect(cornersInOrder(unitCorners), isTrue);
    expect(
      cornersInOrder(const [
        Offset(0, 0),
        Offset(1, 1),
        Offset(1, 0),
        Offset(0, 1),
      ]),
      isFalse,
    );
  });

  testWidgets('drag the handles onto the monitor and use the photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final photo = (await tester.runAsync(monitorPhoto))!;
    AlignedScreenPhoto? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScreenCornerCropScreen(photo: photo),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Align to monitor'), findsOneWidget);

    // Map photo px to the screen: the photo is fitted into the canvas.
    final canvas = tester.getRect(
      find
          .descendant(
            of: find.byType(ScreenCornerCropScreen),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    final fit = math.min(
      (canvas.width - 32) / photoW,
      (canvas.height - 32) / photoH,
    );
    final origin =
        canvas.topLeft +
        Offset(
          (canvas.width - photoW * fit) / 2,
          (canvas.height - photoH * fit) / 2,
        );
    Offset view(Offset px) => origin + px * fit;

    final start = [
      const Offset(120, 90),
      const Offset(1080, 90),
      const Offset(1080, 810),
      const Offset(120, 810),
    ];
    for (var i = 0; i < 4; i++) {
      final target = photoOf(unitCorners[i]);
      await tester.dragFrom(view(start[i]), view(target) - view(start[i]));
      await tester.pumpAndSettle();
    }
    // No screen shape to pick: it is taken from the corners.
    expect(find.textContaining('Screen'), findsNothing);

    await tester.tap(find.text('Use photo'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.aspect, 16 / 10);
    final img = result!.image;
    expect(img.width, 2560);
    final centre = (await tester.runAsync(
      () => pixel(img, const Offset(1280, 800)),
    ))!;
    expect(centre.r, greaterThan(0.8));
    expect(centre.b, lessThan(0.2));
  });

  testWidgets('a later photo keeps the first photo\'s screen shape', (
    tester,
  ) async {
    final photo = (await tester.runAsync(monitorPhoto))!;
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenCornerCropScreen(photo: photo, screenAspect: 16 / 9),
      ),
    );
    await tester.pumpAndSettle();
    // The default corners outline a 1200:900 photo, not a 16:9 screen.
    expect(find.textContaining('different screen shape'), findsOneWidget);
  });
}
