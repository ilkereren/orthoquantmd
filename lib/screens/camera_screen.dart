import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart'; // Add import
import 'package:ortho_quant_md/main.dart'; // import to access global `cameras`
import 'dart:io';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInit = false;
  XFile? _capturedImage;
  Offset? _focusPoint;
  bool _showFocusCircle = false;


  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    // Use the first camera (usually back camera)
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isInit = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final XFile file = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {
        _capturedImage = file;
      });
    } catch (e) {
      debugPrint('Error capturing picture: $e');
    }
  }

  Future<void> _onTap(TapDownDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    try {
      await _controller!.setExposurePoint(offset);
      await _controller!.setFocusPoint(offset);
      
      if (mounted) {
        setState(() {
          _focusPoint = details.localPosition;
          _showFocusCircle = true;
        });
        
        // Hide focus circle after 1.5 seconds
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _showFocusCircle = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error setting focus/exposure: $e');
    }
  }

  Future<void> _cropImage() async {
    if (_capturedImage == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _capturedImage!.path,
      uiSettings: [
        AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false),
        IOSUiSettings(
          title: 'Crop Image',
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        _capturedImage = XFile(croppedFile.path); 
      });
    }
  }

  void _retakePicture() {
    setState(() {
      _capturedImage = null;
      // Re-initialize or resume preview if needed? 
      // CameraController keeps running, we just hid the preview.
    });
  }

  void _confirmPicture() {
    if (_capturedImage != null) {
      Navigator.of(context).pop(_capturedImage!.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_capturedImage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Image.file(
                  File(_capturedImage!.path),
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _retakePicture,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: const Text('Retake'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.crop, color: Colors.white, size: 28),
                      onPressed: _cropImage,
                      tooltip: 'Crop Image',
                    ),
                    ElevatedButton(
                      onPressed: _confirmPicture,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      child: const Text('Use Photo'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Camera Preview with Tap Gesture
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _onTap(details, constraints),
                child: Stack(
                  children: [
                    Center(child: CameraPreview(_controller!)),
                    // Focus Indicator
                    if (_focusPoint != null && _showFocusCircle)
                      Positioned(
                        left: _focusPoint!.dx - 24,
                        top: _focusPoint!.dy - 24,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 2),
                            shape: BoxShape.rectangle,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          
          // Grid Overlay
          Positioned.fill(
            child: IgnorePointer( // Ensure taps pass through to GestureDetector
              child: CustomPaint(
                painter: GridPainter(),
              ),
            ),
          ),
          
          // Back Button
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Capture Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                onPressed: _takePicture,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw vertical lines
    final double colWidth = size.width / 3;
    canvas.drawLine(Offset(colWidth, 0), Offset(colWidth, size.height), paint);
    canvas.drawLine(Offset(colWidth * 2, 0), Offset(colWidth * 2, size.height), paint);

    // Draw horizontal lines
    final double rowHeight = size.height / 3;
    canvas.drawLine(Offset(0, rowHeight), Offset(size.width, rowHeight), paint);
    canvas.drawLine(Offset(0, rowHeight * 2), Offset(size.width, rowHeight * 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
