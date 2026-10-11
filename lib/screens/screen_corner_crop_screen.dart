import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/homography.dart';
import '../widgets/magnifier_overlay_painter.dart';

const _accent = Color(0xFF00BFA5);
const _cornerColor = Color(0xFFFFD766);
const _cornerNames = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];

/// Height in px of every straightened photo. All photos of one measurement
/// share it (and the screen shape), so the same spot on the monitor lands on
/// the same pixel in each of them.
const int alignedScreenHeight = 1600;

/// Common monitor shapes (width / height), landscape and portrait.
const screenShapes = <double>[
  16 / 9,
  16 / 10,
  3 / 2,
  4 / 3,
  5 / 4,
  4 / 5,
  3 / 4,
  10 / 16,
  9 / 16,
];

/// [estimate] snapped to a common monitor shape when it is that close.
double snapScreenShape(double estimate) {
  final nearest = screenShapes.reduce(
    (b, c) =>
        (math.log(c / estimate)).abs() < (math.log(b / estimate)).abs() ? c : b,
  );
  return (math.log(nearest / estimate)).abs() < 0.04 ? nearest : estimate;
}

/// A photo straightened onto the monitor's screen plane.
class AlignedScreenPhoto {
  final ui.Image image;

  /// Width / height of the screen it was straightened to.
  final double aspect;
  const AlignedScreenPhoto(this.image, this.aspect);
}

/// Straightens [photo] so that [corners] (top-left, top-right, bottom-right,
/// bottom-left, in photo px) become the corners of an upright screen of the
/// given [aspect], [alignedScreenHeight] px high.
Future<ui.Image> straightenScreenPhoto(
  ui.Image photo,
  List<Offset> corners,
  double aspect,
) async {
  final h = alignedScreenHeight;
  final w = (h * aspect).round();
  final toScreen = Homography.fromCorners(corners, [
    Offset.zero,
    Offset(w.toDouble(), 0),
    Offset(w.toDouble(), h.toDouble()),
    Offset(0, h.toDouble()),
  ])!;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = Colors.black,
  );
  canvas.transform(toScreen.toMatrix4());
  canvas.drawImage(
    photo,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(w, h);
}

/// True when the four corners form a convex quad in the order shown.
bool cornersInOrder(List<Offset> c) {
  double cross(Offset a, Offset b, Offset p) =>
      (b.dx - a.dx) * (p.dy - b.dy) - (b.dy - a.dy) * (p.dx - b.dx);
  for (var i = 0; i < 4; i++) {
    if (cross(c[i], c[(i + 1) % 4], c[(i + 2) % 4]) <= 0) return false;
  }
  return true;
}

/// Lets the user drag four handles onto the corners of the monitor in a
/// photo, then returns the photo straightened onto the screen plane.
///
/// The screen shape comes from the photo's perspective; [screenAspect] fixes
/// it when an earlier photo of the same monitor already set it.
class ScreenCornerCropScreen extends StatefulWidget {
  final ui.Image photo;
  final double? screenAspect;

  const ScreenCornerCropScreen({
    super.key,
    required this.photo,
    this.screenAspect,
  });

  @override
  State<ScreenCornerCropScreen> createState() => _ScreenCornerCropScreenState();
}

class _ScreenCornerCropScreenState extends State<ScreenCornerCropScreen> {
  late final List<Offset> _corners;
  int? _dragging;
  Offset? _magnifierAt;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final w = widget.photo.width.toDouble(), h = widget.photo.height.toDouble();
    _corners = [
      Offset(w * 0.1, h * 0.1),
      Offset(w * 0.9, h * 0.1),
      Offset(w * 0.9, h * 0.9),
      Offset(w * 0.1, h * 0.9),
    ];
  }

  double get _estimate => estimateScreenAspect(
    _corners,
    Offset(widget.photo.width / 2, widget.photo.height / 2),
  );

  double get _aspect => widget.screenAspect ?? snapScreenShape(_estimate);

  /// The corners disagree with the shape set by an earlier photo.
  bool get _shapeMismatch =>
      widget.screenAspect != null &&
      (math.log(_estimate / widget.screenAspect!)).abs() > 0.05;

  Future<void> _confirm() async {
    setState(() => _working = true);
    final image = await straightenScreenPhoto(widget.photo, _corners, _aspect);
    if (!mounted) return;
    Navigator.of(context).pop(AlignedScreenPhoto(image, _aspect));
  }

  @override
  Widget build(BuildContext context) {
    final ordered = cornersInOrder(_corners);
    final String hint;
    Color hintColor = Colors.white;
    if (_dragging != null) {
      hint = 'Place on the ${_cornerNames[_dragging!]} corner of the screen';
    } else if (!ordered) {
      hint = 'The corners are crossed. Keep 1–4 clockwise from top-left.';
      hintColor = Colors.orangeAccent;
    } else if (_shapeMismatch) {
      hint =
          'These corners suggest a different screen shape than the first '
          'photo. Check that each one sits on the screen corner.';
      hintColor = Colors.orangeAccent;
    } else {
      hint = 'Drag the four corners onto the corners of the monitor screen';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Align to monitor',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: hintColor, fontSize: 14),
              ),
            ),
          ),
          Expanded(child: _buildCanvas()),
          _buildBottomBar(ordered),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, box) {
        final photo = widget.photo;
        final fit = math.min(
          (box.maxWidth - 32) / photo.width,
          (box.maxHeight - 32) / photo.height,
        );
        final origin = Offset(
          (box.maxWidth - photo.width * fit) / 2,
          (box.maxHeight - photo.height * fit) / 2,
        );
        Offset toView(Offset px) => origin + px * fit;
        Offset toPhoto(Offset view) => (view - origin) / fit;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  int? best;
                  var bestDist = 56.0;
                  for (var i = 0; i < 4; i++) {
                    final dist =
                        (toView(_corners[i]) - d.localPosition).distance;
                    if (dist < bestDist) {
                      best = i;
                      bestDist = dist;
                    }
                  }
                  setState(() {
                    _dragging = best;
                    _magnifierAt = best == null ? null : toView(_corners[best]);
                  });
                },
                onPanUpdate: (d) {
                  final i = _dragging;
                  if (i == null) return;
                  final p = toPhoto(toView(_corners[i]) + d.delta);
                  setState(() {
                    _corners[i] = Offset(
                      p.dx.clamp(0, photo.width.toDouble()),
                      p.dy.clamp(0, photo.height.toDouble()),
                    );
                    _magnifierAt = toView(_corners[i]);
                  });
                },
                onPanEnd: (_) => setState(() {
                  _dragging = null;
                  _magnifierAt = null;
                }),
                child: CustomPaint(
                  painter: _CropPainter(
                    photo: photo,
                    corners: _corners,
                    origin: origin,
                    fit: fit,
                    active: _dragging,
                  ),
                ),
              ),
            ),
            if (_magnifierAt != null)
              _magnifier(_magnifierAt!, Size(box.maxWidth, box.maxHeight)),
          ],
        );
      },
    );
  }

  /// Loupe over the dragged corner. Monitor corners often sit near the
  /// photo's edge, so it stays inside the view: above the finger, or below
  /// it when there is no room, and slid sideways near the left/right edge.
  Widget _magnifier(Offset at, Size view) {
    const size = 125.0, gap = 20.0;
    final left = (at.dx - size / 2)
        .toDouble()
        .clamp(8.0, math.max(8.0, view.width - size - 8))
        .toDouble();
    final above = at.dy - size - gap;
    final top = above >= 0 ? above : at.dy + gap;
    final centre = Offset(left + size / 2, top + size / 2);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: RawMagnifier(
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            shadows: [
              BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
            ],
          ),
          size: const Size(size, size),
          magnificationScale: 2,
          focalPointOffset: at - centre,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: MagnifierOverlayPainter()),
              ),
              const Center(
                child: SizedBox(
                  width: 6,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool ordered) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              TextButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: ordered && !_working ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                child: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Use photo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image photo;
  final List<Offset> corners;
  final Offset origin;
  final double fit;
  final int? active;

  _CropPainter({
    required this.photo,
    required this.corners,
    required this.origin,
    required this.fit,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(fit);
    canvas.drawImage(
      photo,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    // Outline of the photo, so a dark photo's edges stay visible.
    canvas.drawRect(
      origin & Size(photo.width * fit, photo.height * fit),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final pts = [for (final c in corners) origin + c * fit];
    final quad = Path()..addPolygon(pts, true);

    // Dim everything outside the screen.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        quad,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      quad,
      Paint()
        ..color = _cornerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < 4; i++) {
      if (i == active) {
        // Hollow while dragged, so the loupe shows the monitor corner under
        // it instead of the handle.
        final cross = Paint()
          ..color = _cornerColor
          ..strokeWidth = 1;
        canvas.drawLine(
          pts[i] - const Offset(22, 0),
          pts[i] + const Offset(22, 0),
          cross,
        );
        canvas.drawLine(
          pts[i] - const Offset(0, 22),
          pts[i] + const Offset(0, 22),
          cross,
        );
        canvas.drawCircle(
          pts[i],
          14,
          Paint()
            ..color = _cornerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        continue;
      }
      const r = 13.0;
      canvas.drawCircle(pts[i], r, Paint()..color = _cornerColor);
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pts[i] - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
