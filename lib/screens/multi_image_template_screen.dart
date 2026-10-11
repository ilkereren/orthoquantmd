import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/multi_image_session.dart';
import '../services/settings_service.dart';
import '../templates/multi_image/multi_image_template.dart';
import '../widgets/magnifier_overlay_painter.dart';
import '../widgets/measurement_boxes.dart';
import '../widgets/monitor_reference_guide.dart';
import 'camera_screen.dart';
import 'screen_corner_crop_screen.dart';
import 'settings_screen.dart';

const _accent = Color(0xFF00BFA5);

// ============================================================ step state

class ImageStepState {
  /// 2 when this image is calibrated itself, 0 when it inherits calibration.
  final int calibrationPointCount;
  ImageStepState(this.calibrationPointCount);

  ui.Image? image;

  /// File the image was loaded from, when there is one (camera, gallery,
  /// a stored session); used to persist the original on DONE.
  String? sourcePath;
  final List<Offset> points = []; // native image px; [0,1] = calibration
  double? calibrationMm;

  double? get ownMmPerPx {
    if (calibrationPointCount == 0 ||
        points.length < 2 ||
        calibrationMm == null ||
        calibrationMm! <= 0) {
      return null;
    }
    final px = (points[1] - points[0]).distance;
    return px == 0 ? null : calibrationMm! / px;
  }

  void reset() {
    points.clear();
    calibrationMm = null;
  }
}

// ============================================================ screen

/// Returned by [MultiImageTemplateScreen] when the user taps DONE.
class MultiImageResult {
  /// Combined view (base image with the overlays), stored in documents.
  final String compositePath;
  final MultiImageSession session;
  const MultiImageResult({required this.compositePath, required this.session});
}

/// Step-by-step flow for a [MultiImageTemplate]: one vertical tab per image
/// (load → calibrate → landmarks) and a final Result tab that combines the
/// geometry of all images in one millimetre plane.
///
/// Visually it follows the standard measurement screen: transparent app bar,
/// floating step pill, landmark handles and sizes from the user's settings,
/// magnifier while dragging, [TemplateResultBox] and the bottom tool bar.
class MultiImageTemplateScreen extends StatefulWidget {
  final MultiImageTemplate template;

  /// A stored session to reopen for editing (images, points, calibration).
  final MultiImageSession? initialSession;

  const MultiImageTemplateScreen({
    super.key,
    required this.template,
    this.initialSession,
  });

  @override
  State<MultiImageTemplateScreen> createState() =>
      _MultiImageTemplateScreenState();
}

class _MultiImageTemplateScreenState extends State<MultiImageTemplateScreen> {
  late final List<ImageStepState> _steps = [
    for (final spec in widget.template.steps)
      ImageStepState(spec.calibrate ? 2 : 0),
  ];
  int _tab = 0;
  int _resultBackground = 0;
  double _overlayOpacity = 0.5;
  Offset _resultBoxOffset = const Offset(12, 12);

  bool _finishing = false;

  /// Width / height of the monitor every photo is straightened to; set by
  /// the first aligned photo so all of them share one screen plane.
  double? _screenAspect;

  @override
  void initState() {
    super.initState();
    final session = widget.initialSession;
    if (session != null) {
      _restore(session);
    } else {
      // New measurement: explain how to photograph the monitor, then take
      // or choose the first photo right away.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final source = widget.template.alignToMonitor
            ? await showMonitorReferenceGuide(context, canTakePhoto: _isMobile)
            : await showRotationGuide(context, canTakePhoto: _isMobile);
        if (source != null && mounted) await _pickFrom(0, source);
      });
    }
  }

  Future<void> _restore(MultiImageSession session) async {
    for (var i = 0; i < session.images.length && i < _steps.length; i++) {
      final e = session.images[i];
      final file = File(e.path);
      if (!await file.exists()) continue;
      final img = await _decode(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        _steps[i]
          ..image = img
          ..sourcePath = e.path
          ..reset()
          ..points.addAll(e.points)
          ..calibrationMm = e.calibrationMm;
      });
    }
    if (!mounted) return;
    setState(() {
      _screenAspect = session.screenAspect;
      _resultBackground = session.baseIndex.clamp(0, _steps.length - 1);
      _overlayOpacity = session.overlayOpacity;
      if (_tabUnlocked(_resultTab)) _tab = _resultTab;
    });
  }

  int get _resultTab => widget.template.steps.length;

  /// Index of the image whose calibration step [i] uses.
  int _calibrationSource(int i) {
    for (var j = i; j >= 0; j--) {
      if (widget.template.steps[j].calibrate) return j;
    }
    return 0;
  }

  /// Angle-only templates are not calibrated: every straightened image has
  /// the same px scale, so 1 unit per px is enough.
  double? _mmPerPx(int i) => widget.template.usesCalibration
      ? _steps[_calibrationSource(i)].ownMmPerPx
      : 1;

  bool _stepComplete(int i) {
    final st = _steps[i];
    return st.image != null &&
        _mmPerPx(i) != null &&
        st.points.length ==
            st.calibrationPointCount +
                widget.template.steps[i].landmarks.length;
  }

  bool _tabUnlocked(int tab) {
    for (var i = 0; i < tab && i < _steps.length; i++) {
      if (!_stepComplete(i)) return false;
    }
    return true;
  }

  /// Every placed anatomical landmark, in the common mm plane.
  Map<String, Offset> _allMm() => landmarksInMm(
    widget.template,
    [for (final st in _steps) st.points],
    [for (final st in _steps) st.calibrationPointCount],
    [for (var i = 0; i < _steps.length; i++) _mmPerPx(i)],
  );

  Map<String, Offset> _mmExcept(int step) {
    final all = _allMm();
    for (final l in widget.template.steps[step].landmarks) {
      all.remove(l.id);
    }
    return all;
  }

  // ---------------------------------------------------------------- loading

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Same sources as the home screen: photograph the monitor, or pick a
  /// saved image; then align it to the monitor. Desktop and web use a file
  /// picker.
  Future<void> _pick(int i) async {
    if (!_isMobile) return _pickFrom(i, MonitorPhotoSource.gallery);
    final source = await showModalBottomSheet<MonitorPhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: _accent),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, MonitorPhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Color(0xFF2979FF),
              ),
              title: const Text('Select from Gallery'),
              onTap: () => Navigator.pop(context, MonitorPhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    await _pickFrom(i, source);
  }

  /// Takes or picks a photo of the monitor for image [i], then lets the
  /// user drag its corners onto the screen and straightens it.
  Future<void> _pickFrom(int i, MonitorPhotoSource source) async {
    Uint8List? bytes;
    if (!_isMobile) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      bytes = result?.files.single.bytes;
    } else if (source == MonitorPhotoSource.camera) {
      final result = await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => const CameraScreen()));
      if (result is String) bytes = await File(result).readAsBytes();
    } else {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) bytes = await picked.readAsBytes();
    }
    if (bytes == null || !mounted) return;

    final photo = await _decode(bytes);
    if (!mounted) return;
    if (!widget.template.alignToMonitor) {
      setState(() {
        _steps[i]
          ..image = photo
          ..sourcePath = null
          ..reset();
      });
      return;
    }
    // The first aligned photo sets the screen shape; later ones (and a
    // replacement while another image is loaded) must use the same.
    final otherLoaded = [
      for (var j = 0; j < _steps.length; j++)
        if (j != i && _steps[j].image != null) j,
    ].isNotEmpty;
    final aligned = await Navigator.of(context).push<AlignedScreenPhoto>(
      MaterialPageRoute(
        builder: (context) => ScreenCornerCropScreen(
          photo: photo,
          screenAspect: otherLoaded ? _screenAspect : null,
        ),
      ),
    );
    if (aligned == null || !mounted) return;
    setState(() {
      _screenAspect = aligned.aspect;
      _steps[i]
        ..image = aligned.image
        ..sourcePath = null
        ..reset();
    });
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  Future<void> _loadDemo(int i) async {
    final img = await _DemoImages.render(i);
    if (!mounted) return;
    setState(() {
      _steps[i]
        ..image = img
        ..sourcePath = null
        ..reset();
    });
  }

  // ---------------------------------------------------------------- DONE

  /// Persists the source images and the combined view, then returns the
  /// result to the caller, which shows it on the standard screen.
  Future<void> _finish() async {
    if (kIsWeb || _finishing) return;
    setState(() => _finishing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final entries = <MultiImageEntry>[];
      for (var i = 0; i < _steps.length; i++) {
        final st = _steps[i];
        entries.add(
          MultiImageEntry(
            path: await _persistImage(
              st,
              '${dir.path}/mi_${stamp}_$i',
              dir.path,
            ),
            points: List.of(st.points),
            calibrationMm: st.calibrationMm,
            calibrationPointCount: st.calibrationPointCount,
          ),
        );
      }
      final session = MultiImageSession(
        templateId: widget.template.id,
        images: entries,
        baseIndex: _resultBackground,
        overlayOpacity: _overlayOpacity,
        screenAspect: _screenAspect,
      );
      final compositePath = '${dir.path}/mi_${stamp}_combined.png';
      await File(compositePath).writeAsBytes(await _renderComposite());
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(MultiImageResult(compositePath: compositePath, session: session));
    } catch (e) {
      debugPrint('Multi-image finish failed: $e');
      if (mounted) {
        setState(() => _finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the images.')),
        );
      }
    }
  }

  /// Keeps a stored original as is; copies a picked file, or encodes the
  /// decoded image when there is no file (e.g. demo images).
  Future<String> _persistImage(
    ImageStepState st,
    String basePath,
    String docsDir,
  ) async {
    final src = st.sourcePath;
    if (src != null && await File(src).exists()) {
      if (src.startsWith(docsDir)) return src;
      final dot = src.lastIndexOf('.');
      final ext = dot > src.lastIndexOf('/') ? src.substring(dot) : '.png';
      await File(src).copy('$basePath$ext');
      return '$basePath$ext';
    }
    final data = await st.image!.toByteData(format: ui.ImageByteFormat.png);
    await File('$basePath.png').writeAsBytes(data!.buffer.asUint8List());
    return '$basePath.png';
  }

  /// Base image with the other images over it at the chosen opacity, placed
  /// by calibration only. Geometry is not baked in; the standard screen
  /// draws it live.
  Future<Uint8List> _renderComposite() async {
    final base = _steps[_resultBackground].image!;
    final kBase = _mmPerPx(_resultBackground)!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(base, Offset.zero, Paint());
    for (var i = 0; i < _steps.length; i++) {
      if (i == _resultBackground || _overlayOpacity <= 0) continue;
      canvas.save();
      canvas.scale(_mmPerPx(i)! / kBase);
      canvas.drawImage(
        _steps[i].image!,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.high
          ..color = Color.fromRGBO(255, 255, 255, _overlayOpacity),
      );
      canvas.restore();
    }
    final image = await recorder.endRecording().toImage(
      base.width,
      base.height,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  // ---------------------------------------------------------------- actions

  void _addPoint(int i, Offset p) {
    final st = _steps[i];
    setState(() => st.points.add(p));
    if (st.calibrationPointCount == 2 && st.points.length == 2) {
      _showCalibrationDialog(i);
    }
  }

  void _undo(int i) {
    final st = _steps[i];
    if (st.points.isEmpty) return;
    setState(() {
      st.points.removeLast();
      if (st.points.length < 2) st.calibrationMm = null;
    });
  }

  /// Same dialog as the standard screen's "Calibrate Scale".
  void _showCalibrationDialog(int i) {
    final st = _steps[i];
    double? suggested = st.calibrationMm;
    for (var j = i - 1; suggested == null && j >= 0; j--) {
      suggested = _steps[j].calibrationMm;
    }
    final controller = TextEditingController(
      text: suggested == null
          ? ''
          : suggested.toStringAsFixed(suggested % 1 == 0 ? 0 : 1),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calibrate Scale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the real-world distance for this line in mm:'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Distance (mm)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null && val > 0) {
                setState(() => st.calibrationMm = val);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'OrthoQuant MD',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              if (mounted) setState(() {}); // pick up style changes
            },
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildTabRail(),
                Expanded(
                  child: _tab == _resultTab
                      ? _buildResultTab()
                      : _buildImageTab(_tab),
                ),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  /// Narrow vertical tab strip so the image keeps the full width.
  Widget _buildTabRail() {
    final labels = [
      for (var i = 0; i < _steps.length; i++) 'Image ${i + 1}',
      'Result',
    ];
    return Container(
      width: 40,
      color: Colors.black,
      child: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: _buildRailTab(i, labels[i])),
        ],
      ),
    );
  }

  Widget _buildRailTab(int i, String label) {
    final selected = _tab == i;
    final unlocked = _tabUnlocked(i);
    final done = i < _steps.length && _stepComplete(i);
    final color = !unlocked
        ? Colors.white24
        : (selected ? _accent : Colors.white70);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: unlocked ? () => setState(() => _tab = i) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!unlocked)
                  Icon(Icons.lock, size: 13, color: color)
                else if (done)
                  const Icon(Icons.check_circle, size: 13, color: _accent),
                if (!unlocked || done) const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Floating instruction pill, styled like the standard template wizard.
  Widget _buildStepPill(String badge, String text, {Color? badgeColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor ?? Colors.yellowAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTab(int i) {
    final spec = widget.template.steps[i];
    final st = _steps[i];
    if (st.image == null) return _buildLoadPrompt(i, spec);

    final cal = st.calibrationPointCount;
    final total = cal + spec.landmarks.length;
    final placed = st.points.length;
    final needsMm = cal == 2 && placed >= 2 && st.ownMmPerPx == null;

    final Widget pill;
    if (cal == 2 && placed == 0) {
      pill = _buildStepPill(
        'CAL',
        'Mark the start of a known length (e.g. scale bar)',
      );
    } else if (cal == 2 && placed == 1) {
      pill = _buildStepPill('CAL', 'Mark the end of the known length');
    } else if (needsMm) {
      pill = _buildStepPill('CAL', 'Tap Calibrate and enter the length in mm');
    } else if (placed < total) {
      final l = spec.landmarks[placed - cal];
      pill = _buildStepPill(
        '${placed - cal + 1} / ${spec.landmarks.length}',
        '${l.label}: ${l.instruction}',
      );
    } else {
      pill = _buildStepPill(
        '✓',
        i + 1 < _steps.length
            ? 'Image ${i + 1} complete. Tap Next.'
            : 'All images complete. Tap Result.',
        badgeColor: _accent,
      );
    }

    final inherited =
        cal == 0 && widget.template.usesCalibration && _mmPerPx(i) != null;

    return Stack(
      children: [
        Positioned.fill(
          child: _ImageCanvas(
            image: st.image!,
            canPlace: !needsMm && placed < total,
            onTap: (p) => _addPoint(i, p),
            editablePoints: st.points,
            onMovePoint: (idx, p) => setState(() => st.points[idx] = p),
            painterBuilder: (scale) => _StepPainter(
              image: st.image!,
              points: st.points,
              labels: [
                if (cal == 2) ...['', ''],
                ...spec.landmarks.map((l) => l.label),
              ],
              calibrationPoints: cal,
              calibrationMm: st.calibrationMm,
              scale: scale,
              template: widget.template,
              ghostMm: _mmExcept(i),
              mmPerPx: _mmPerPx(i),
            ),
          ),
        ),
        Positioned(top: 10, left: 12, right: 12, child: pill),
        if (inherited)
          Positioned(
            left: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[900]?.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Calibration from Image ${_calibrationSource(i) + 1} · '
                '${_mmPerPx(i)!.toStringAsFixed(3)} mm/px',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadPrompt(int i, ImageStepSpec spec) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              size: 44,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              'Image ${i + 1} · ${spec.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              spec.loadPrompt,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _pick(i),
              icon: const Icon(Icons.photo_library),
              label: const Text('Load image'),
            ),
            if (kDebugMode)
              TextButton(
                onPressed: () => _loadDemo(i),
                child: const Text(
                  'Demo image',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTab() {
    final mm = _allMm();
    final results = widget.template.calculate(mm);
    final bg = _steps[_resultBackground];
    final k = _mmPerPx(_resultBackground)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: _ImageCanvas(
                image: bg.image!,
                canPlace: false,
                onTap: (_) {},
                painterBuilder: (scale) => _ResultPainter(
                  image: bg.image!,
                  overlays: [
                    for (var i = 0; i < _steps.length; i++)
                      if (i != _resultBackground)
                        // Placed by calibration only: px → mm → bg px.
                        (_steps[i].image!, _mmPerPx(i)! / k),
                  ],
                  overlayOpacity: _overlayOpacity,
                  template: widget.template,
                  mm: mm,
                  mmPerPx: k,
                  scale: scale,
                ),
              ),
            ),
            // Draggable result box, as on the standard screen.
            Positioned(
              left: _resultBoxOffset.dx,
              top: _resultBoxOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  final next = _resultBoxOffset + d.delta;
                  _resultBoxOffset = Offset(
                    next.dx.clamp(0, math.max(0, constraints.maxWidth - 220)),
                    next.dy.clamp(0, math.max(0, constraints.maxHeight - 80)),
                  );
                }),
                child: TemplateResultBox(
                  title: widget.template.title,
                  items: [
                    for (final r in results)
                      {'label': r.label, 'value': r.value},
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 60,
              child: Text(
                widget.template.alignToMonitor
                    ? 'Photos are straightened by the monitor corners. Keep '
                          'the viewer zoom and pan unchanged between them.'
                    : 'Any rotation between the two images changes the '
                          'angle.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
                ),
              ),
            ),
            if (_finishing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[900]?.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.layers, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Overlay',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        activeColor: _accent,
                        value: _overlayOpacity,
                        onChanged: (v) => setState(() => _overlayOpacity = v),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${(_overlayOpacity * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Bottom tool bar with the same button style as the standard screen.
  Widget _buildBottomBar() {
    final List<Widget> buttons;
    if (_tab == _resultTab) {
      buttons = [
        for (var i = 0; i < _steps.length; i++)
          _bottomButton(
            icon: Icons.image_outlined,
            label: 'Base: Image ${i + 1}',
            isActive: _resultBackground == i,
            onTap: () => setState(() => _resultBackground = i),
          ),
        _bottomButton(
          icon: Icons.check_circle,
          label: 'DONE',
          isActive: true,
          enabled: !_finishing,
          onTap: _finish,
        ),
      ];
    } else {
      final i = _tab;
      final st = _steps[i];
      final hasImage = st.image != null;
      final cal = st.calibrationPointCount;
      final total = cal + widget.template.steps[i].landmarks.length;
      final complete = _stepComplete(i);
      buttons = [
        _bottomButton(
          icon: Icons.undo,
          label: 'Undo',
          enabled: st.points.isNotEmpty,
          onTap: () => _undo(i),
        ),
        if (cal == 2)
          _bottomButton(
            icon: Icons.straighten,
            label: st.ownMmPerPx == null
                ? 'Calibrate'
                : '${st.calibrationMm!.toStringAsFixed(0)} mm',
            enabled: st.points.length >= 2,
            isActive: st.points.length >= 2 && st.ownMmPerPx == null,
            onTap: () => _showCalibrationDialog(i),
          ),
        _bottomButton(
          icon: Icons.photo_library_outlined,
          label: 'Replace',
          enabled: hasImage,
          onTap: () => _pick(i),
        ),
        _bottomButton(
          icon: i + 1 < _steps.length ? Icons.arrow_forward : Icons.assessment,
          label: i + 1 < _steps.length ? 'Next' : 'Result',
          enabled: complete,
          isActive: complete && st.points.length == total,
          onTap: () => setState(() => _tab = i + 1),
        ),
      ];
    }
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: buttons,
          ),
        ),
      ),
    );
  }

  Widget _bottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool enabled = true,
  }) {
    final color = !enabled
        ? Colors.white24
        : (isActive ? _accent : Colors.white70);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isActive && enabled
                      ? Colors.white24
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: color, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ canvas

/// Horizontal scale factor of a view transform (z is ignored on purpose:
/// it stays 1 when the image is shrunk to fit).
double _viewScale(Matrix4 m) => Offset(m.entry(0, 0), m.entry(1, 0)).distance;

/// Pan/zoom viewer whose child coordinates are native image pixels, so taps
/// are stored without any rescaling. Points can be dragged; a magnifier is
/// shown while dragging, as on the standard screen.
class _ImageCanvas extends StatefulWidget {
  final ui.Image image;
  final bool canPlace;
  final ValueChanged<Offset> onTap;
  final CustomPainter Function(double scale) painterBuilder;

  /// Points (native px) that can be grabbed and dragged to a new position.
  final List<Offset> editablePoints;
  final void Function(int index, Offset position)? onMovePoint;

  const _ImageCanvas({
    required this.image,
    required this.canPlace,
    required this.onTap,
    required this.painterBuilder,
    this.editablePoints = const [],
    this.onMovePoint,
  });

  @override
  State<_ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<_ImageCanvas> {
  final _controller = TransformationController();
  Size? _fittedFor;
  ui.Image? _fittedImage;
  int? _dragging;
  Offset? _magnifierAt; // viewport coordinates

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    final w = widget.image.width.toDouble(), h = widget.image.height.toDouble();
    final s = math.min(viewport.width / w, viewport.height / h);
    final dx = (viewport.width - w * s) / 2, dy = (viewport.height - h * s) / 2;
    _controller.value = Matrix4(
      s,
      0,
      0,
      0,
      0,
      s,
      0,
      0,
      0,
      0,
      s,
      0,
      dx,
      dy,
      0,
      1,
    );
  }

  /// Nearest editable point within a fixed on-screen radius.
  int? _hitPoint(Offset local) {
    if (widget.onMovePoint == null) return null;
    final radius = 24 / _viewScale(_controller.value);
    int? best;
    var bestDist = radius;
    for (var i = 0; i < widget.editablePoints.length; i++) {
      final d = (widget.editablePoints[i] - local).distance;
      if (d <= bestDist) {
        best = i;
        bestDist = d;
      }
    }
    return best;
  }

  void _endDrag() => setState(() {
    _dragging = null;
    _magnifierAt = null;
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final viewport = c.biggest;
        if (_fittedFor != viewport || _fittedImage != widget.image) {
          _fittedFor = viewport;
          _fittedImage = widget.image;
          _fit(viewport);
        }
        return Listener(
          // Viewport-space position for the magnifier.
          onPointerMove: (e) {
            if (_dragging != null)
              setState(() => _magnifierAt = e.localPosition);
          },
          child: Stack(
            children: [
              ClipRect(
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: 0.05,
                  maxScale: 40,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  // While a point is grabbed the viewer must not pan.
                  panEnabled: _dragging == null,
                  child: Listener(
                    onPointerDown: (e) {
                      final hit = _hitPoint(e.localPosition);
                      if (hit != null) setState(() => _dragging = hit);
                    },
                    onPointerMove: (e) {
                      final i = _dragging;
                      if (i != null) widget.onMovePoint!(i, e.localPosition);
                    },
                    onPointerUp: (_) => _endDrag(),
                    onPointerCancel: (_) => _endDrag(),
                    child: GestureDetector(
                      onTapUp: widget.canPlace
                          ? (d) {
                              // A tap on an existing point grabs it instead
                              // of adding one.
                              if (_hitPoint(d.localPosition) == null) {
                                widget.onTap(d.localPosition);
                              }
                            }
                          : null,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => CustomPaint(
                          size: Size(
                            widget.image.width.toDouble(),
                            widget.image.height.toDouble(),
                          ),
                          painter: widget.painterBuilder(
                            _viewScale(_controller.value),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_magnifierAt != null)
                Positioned(
                  left: _magnifierAt!.dx - 62.5,
                  top: _magnifierAt!.dy - 145,
                  child: RawMagnifier(
                    decoration: const MagnifierDecoration(
                      shape: CircleBorder(
                        side: BorderSide(color: Colors.white, width: 2),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    size: const Size(125, 125),
                    magnificationScale: 1.5,
                    focalPointOffset: const Offset(0, 82.5),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: MagnifierOverlayPainter(),
                          ),
                        ),
                        Center(
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
            ],
          ),
        );
      },
    );
  }
}

/// Draws an image-tab: image, other images' geometry as ghosts, calibration
/// line and landmarks in the standard landmark style.
class _StepPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> points;
  final List<String> labels;
  final int calibrationPoints;
  final double? calibrationMm;
  final double scale;
  final MultiImageTemplate template;
  final Map<String, Offset> ghostMm;
  final double? mmPerPx;

  _StepPainter({
    required this.image,
    required this.points,
    required this.labels,
    required this.calibrationPoints,
    required this.calibrationMm,
    required this.scale,
    required this.template,
    required this.ghostMm,
    required this.mmPerPx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = 1 / scale;
    final settings = SettingsService();
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final k = mmPerPx;
    if (k != null && ghostMm.isNotEmpty) {
      template.paintGhost(canvas, ghostMm, (mm) => mm / k, s);
    }

    if (calibrationPoints == 2 && points.length >= 2) {
      canvas.drawLine(
        points[0],
        points[1],
        Paint()
          ..color = Colors.white
          ..strokeWidth = settings.lineThickness * s,
      );
      _text(
        canvas,
        calibrationMm == null
            ? 'Set Scale'
            : '${calibrationMm!.toStringAsFixed(0)} mm',
        (points[0] + points[1]) / 2 + Offset(0, -28 * s),
        settings.textSize * s,
      );
    }

    final radius = (settings.landmarkSize * 5.0 / 2) * s;
    for (var i = 0; i < points.length; i++) {
      final isCal = i < calibrationPoints;
      canvas.drawCircle(
        points[i],
        radius,
        Paint()..color = isCal ? Colors.white : Colors.black,
      );
      canvas.drawCircle(
        points[i],
        radius,
        Paint()
          ..color = isCal ? Colors.black54 : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = (isCal ? 1.0 : 2.0) * s,
      );
      if (labels[i].isNotEmpty) {
        _text(
          canvas,
          labels[i],
          points[i] + Offset(radius + 6 * s, 4 * s),
          settings.textSize * 0.85 * s,
          center: false,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double fontSize, {
    bool center = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: SettingsService().textBold ? FontWeight.bold : null,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _ResultPainter extends CustomPainter {
  final ui.Image image;

  /// Other images with their px scale relative to [image], derived from
  /// calibration (1.0 when they share it). Never fitted by eye.
  final List<(ui.Image, double)> overlays;
  final double overlayOpacity;
  final MultiImageTemplate template;
  final Map<String, Offset> mm;
  final double mmPerPx;
  final double scale;

  _ResultPainter({
    required this.image,
    required this.overlays,
    required this.overlayOpacity,
    required this.template,
    required this.mm,
    required this.mmPerPx,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (overlayOpacity > 0) {
      for (final (img, k) in overlays) {
        canvas.save();
        canvas.scale(k);
        canvas.drawImage(
          img,
          Offset.zero,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(255, 255, 255, overlayOpacity),
        );
        canvas.restore();
      }
    }
    template.paintCombined(canvas, mm, (p) => p / mmPerPx, 1 / scale);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ============================================================ demo images

/// Renders the synthetic demo slice for [step] (debug/test aid).
@visibleForTesting
Future<ui.Image> renderMultiImageDemo(int step) => _DemoImages.render(step);

class _DemoImages {
  static const w = 900, h = 800;
  static const center = Offset(450, 400);
  static const rotationDeg = 8.0;

  static Future<ui.Image> render(int step) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF050505),
    );

    // Scale bar: 200 px = 50 mm.
    final bar = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    c.drawLine(const Offset(60, 740), const Offset(260, 740), bar);
    c.drawLine(const Offset(60, 730), const Offset(60, 750), bar);
    c.drawLine(const Offset(260, 730), const Offset(260, 750), bar);
    final tp = TextPainter(
      text: const TextSpan(
        text: '50 mm',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, const Offset(130, 705));

    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(rotationDeg * math.pi / 180);

    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 560, height: 470),
      Paint()..color = const Color(0xFF3A3A3A),
    );

    final bone = Paint()..color = const Color(0xFFC9C9C9);
    final cortex = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    if (step == 0) {
      // Femoral condyles; posterior-most points at (±100, 120).
      for (final x in [-100.0, 100.0]) {
        c.drawCircle(Offset(x, 40), 80, bone);
        c.drawCircle(Offset(x, 40), 80, cortex);
      }
      final trochlea = Path()
        ..moveTo(-175, 30)
        ..lineTo(-90, -95)
        ..lineTo(0, -60) // deepest groove
        ..lineTo(90, -95)
        ..lineTo(175, 30)
        ..close();
      c.drawPath(trochlea, bone);
      c.drawPath(trochlea, cortex);
      c.drawRect(
        Rect.fromCenter(center: const Offset(0, 20), width: 200, height: 90),
        bone,
      );
      // Patella.
      c.drawOval(
        Rect.fromCenter(center: const Offset(10, -150), width: 150, height: 55),
        bone,
      );
    } else {
      // Proximal tibia with tuberosity; insertion midpoint at (80, -108).
      c.drawOval(
        Rect.fromCenter(center: const Offset(0, 30), width: 340, height: 220),
        bone,
      );
      c.drawOval(
        Rect.fromCenter(center: const Offset(0, 30), width: 340, height: 220),
        cortex,
      );
      c.drawCircle(const Offset(80, -80), 28, bone);
      c.drawCircle(const Offset(80, -80), 28, cortex);
      // Fibular head.
      c.drawCircle(const Offset(200, 110), 30, bone);
      // Patellar tendon.
      c.drawRect(
        Rect.fromCenter(center: const Offset(70, -140), width: 70, height: 26),
        Paint()..color = const Color(0xFF6A6A6A),
      );
    }
    c.restore();
    return rec.endRecording().toImage(w, h);
  }
}
