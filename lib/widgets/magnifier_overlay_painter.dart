import 'package:flutter/material.dart';

/// Brightens the magnified image area by drawing a translucent white layer
/// with [BlendMode.screen]. Used inside the on-image magnifier so dark
/// regions of an X-ray remain readable when zoomed in.
class MagnifierOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Brighten the magnified image using BlendMode.screen.
    // This adds light to the image, making dark areas more visible.
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25) // Adjust opacity for brightness level
      ..blendMode = BlendMode.screen;

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
