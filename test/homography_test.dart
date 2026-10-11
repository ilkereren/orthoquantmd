import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/utils/homography.dart';

/// Pinhole photo of a point on a flat screen: screen (x, y) in mm, screen
/// centred at the origin, camera [dist] mm away, turned by [yaw]/[pitch]
/// degrees, focal length [f] px, principal point [c].
Offset photo(
  Offset s, {
  double yaw = 25,
  double pitch = -15,
  double dist = 700,
  double f = 3000,
  Offset c = const Offset(2000, 1500),
}) {
  final cy = math.cos(yaw * math.pi / 180), sy = math.sin(yaw * math.pi / 180);
  final cp = math.cos(pitch * math.pi / 180);
  final sp = math.sin(pitch * math.pi / 180);
  // Rotate the screen plane, then push it in front of the camera.
  var x = s.dx, y = s.dy, z = 0.0;
  final x1 = cy * x + sy * z, z1 = -sy * x + cy * z;
  x = x1;
  z = z1;
  final y2 = cp * y - sp * z, z2 = sp * y + cp * z;
  y = y2;
  z = z2 + dist;
  return Offset(c.dx + f * x / z, c.dy + f * y / z);
}

void main() {
  const w = 520.0, h = 325.0; // 16:10 screen, mm
  const screen = [
    Offset(-w / 2, -h / 2),
    Offset(w / 2, -h / 2),
    Offset(w / 2, h / 2),
    Offset(-w / 2, h / 2),
  ];
  final corners = [for (final p in screen) photo(p)];

  test('maps photo points back onto the screen plane', () {
    final hom = Homography.fromCorners(corners, screen)!;
    for (final p in const [Offset(0, 0), Offset(123, -80), Offset(-200, 40)]) {
      final back = hom.map(photo(p));
      expect(back.dx, closeTo(p.dx, 1e-6));
      expect(back.dy, closeTo(p.dy, 1e-6));
    }
    final inv = hom.inverse();
    final q = photo(const Offset(50, 60));
    expect((inv.map(hom.map(q)) - q).distance, lessThan(1e-6));
  });

  test('composition maps between two photos of the same screen', () {
    final other = [for (final p in screen) photo(p, yaw: -10, dist: 500)];
    final h1 = Homography.fromCorners(corners, screen)!;
    final h2 = Homography.fromCorners(other, screen)!;
    // Photo 2 px → screen → photo 1 px.
    final m = h1.inverse().after(h2);
    const s = Offset(-70, 90);
    expect(
      (m.map(photo(s, yaw: -10, dist: 500)) - photo(s)).distance,
      lessThan(1e-6),
    );
  });

  test('estimates the true aspect ratio of a tilted screen', () {
    final aspect = estimateScreenAspect(corners, const Offset(2000, 1500));
    expect(aspect, closeTo(16 / 10, 0.01));
    // The raw side ratio in the photo is clearly wrong.
    final rawW = (corners[1] - corners[0]).distance;
    final rawH = (corners[3] - corners[0]).distance;
    expect((rawW / rawH - 1.6).abs(), greaterThan(0.05));
  });

  test('falls back to the side ratio for a frontal photo', () {
    final frontal = [for (final p in screen) photo(p, yaw: 0, pitch: 0)];
    expect(
      estimateScreenAspect(frontal, const Offset(2000, 1500)),
      closeTo(1.6, 1e-6),
    );
  });

  test('rejects degenerate corners', () {
    expect(
      Homography.fromCorners(const [
        Offset(0, 0),
        Offset(1, 1),
        Offset(2, 2),
        Offset(3, 3),
      ], screen),
      isNull,
    );
  });
}
