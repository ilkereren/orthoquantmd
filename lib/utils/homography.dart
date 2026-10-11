import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Projective transform of the plane (3×3, row-major, h[8] normalised to 1).
///
/// Used to map a photo of a monitor onto the monitor's own flat screen
/// plane from its four corners, which removes the camera's distance, tilt
/// and perspective from every point placed on the photo.
class Homography {
  final List<double> h;
  const Homography(this.h);

  /// Maps [src] corners onto [dst] corners (both in the same order).
  /// Returns null when the corners are degenerate (e.g. three collinear).
  static Homography? fromCorners(List<Offset> src, List<Offset> dst) {
    assert(src.length == 4 && dst.length == 4);
    // Solve A·x = b for the 8 unknowns (h22 = 1).
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = src[i].dx, y = src[i].dy, u = dst[i].dx, v = dst[i].dy;
      a[2 * i]
        ..setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y])
        ..[8] = u;
      a[2 * i + 1]
        ..setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y])
        ..[8] = v;
    }
    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return Homography([for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1]);
  }

  Offset map(Offset p) {
    final w = h[6] * p.dx + h[7] * p.dy + h[8];
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / w,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / w,
    );
  }

  Homography inverse() {
    final a = h[0], b = h[1], c = h[2];
    final d = h[3], e = h[4], f = h[5];
    final g = h[6], i = h[7], k = h[8];
    final adj = [
      e * k - f * i, c * i - b * k, b * f - c * e, //
      f * g - d * k, a * k - c * g, c * d - a * f,
      d * i - e * g, b * g - a * i, a * e - b * d,
    ];
    final n = adj[8];
    return Homography([for (final v in adj) v / n]);
  }

  /// `this` after [first]: maps p → this(first(p)).
  Homography after(Homography first) {
    final r = List<double>.filled(9, 0);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        var s = 0.0;
        for (var k = 0; k < 3; k++) {
          s += h[row * 3 + k] * first.h[k * 3 + col];
        }
        r[row * 3 + col] = s;
      }
    }
    return Homography([for (final v in r) v / r[8]]);
  }

  /// Column-major 4×4 matrix for [Canvas.transform], so an image can be
  /// drawn warped by this homography.
  Float64List toMatrix4() => Float64List.fromList([
    h[0], h[3], 0, h[6], //
    h[1], h[4], 0, h[7],
    0, 0, 1, 0,
    h[2], h[5], 0, h[8],
  ]);
}

/// Width / height of the screen rectangle seen in a photo through [corners]
/// (top-left, top-right, bottom-right, bottom-left, in photo pixels).
///
/// Uses the standard single-view rectangle method (Zhang & He): with square
/// pixels and the principal point at the photo centre [principal], the
/// focal length is recovered from the two vanishing points and the true
/// aspect ratio follows. Returns null when the photo is too frontal for the
/// focal length to be determined; the corner side ratio is returned then.
/// The result is a suggestion for the user to confirm, since a cropped photo
/// moves the principal point.
double estimateScreenAspect(List<Offset> corners, Offset principal) {
  // Corners relative to the principal point, as homogeneous vectors.
  List<double> v(Offset p) => [p.dx - principal.dx, p.dy - principal.dy, 1];
  final m1 = v(corners[3]); // bottom-left  ↔ (0, 0)
  final m2 = v(corners[2]); // bottom-right ↔ (w, 0)
  final m3 = v(corners[0]); // top-left     ↔ (0, h)
  final m4 = v(corners[1]); // top-right    ↔ (w, h)

  List<double> cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
  double dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  final c14 = cross(m1, m4);
  final k2 = dot(c14, m3) / dot(cross(m2, m4), m3);
  final k3 = dot(c14, m2) / dot(cross(m3, m4), m2);
  final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
  final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];

  double frontal() {
    final w =
        ((corners[1] - corners[0]).distance +
            (corners[2] - corners[3]).distance) /
        2;
    final h =
        ((corners[3] - corners[0]).distance +
            (corners[2] - corners[1]).distance) /
        2;
    return w / h;
  }

  // Nearly parallel opposite sides: no usable vanishing point.
  if ((k2 - 1).abs() < 0.01 || (k3 - 1).abs() < 0.01) return frontal();

  final f2 = -(n2[0] * n3[0] + n2[1] * n3[1]) / (n2[2] * n3[2]);
  if (f2 <= 0 || !f2.isFinite) return frontal();

  final num = n2[0] * n2[0] + n2[1] * n2[1] + n2[2] * n2[2] * f2;
  final den = n3[0] * n3[0] + n3[1] * n3[1] + n3[2] * n3[2] * f2;
  if (den <= 0) return frontal();
  return math.sqrt(num / den);
}
