import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ortho_quant_md/utils/geometry.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
// import 'package:google_fonts/google_fonts.dart'; // Unused
import 'package:ortho_quant_md/screens/export_screen.dart';
import 'package:ortho_quant_md/models/template_model.dart'; // Ensure this is imported
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/screens/save_record_screen.dart';
import 'package:ortho_quant_md/templates/template_registry.dart'; // NEW
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart'; // NEW

import 'package:ortho_quant_md/screens/settings_screen.dart';
import 'package:ortho_quant_md/services/settings_service.dart';
import 'package:ortho_quant_md/services/history_service.dart';
import 'package:uuid/uuid.dart';
import 'package:ortho_quant_md/services/subscription_service.dart';
import 'package:ortho_quant_md/screens/paywall_screen.dart';
// import 'package:ortho_quant_md/main.dart'; // No longer needed for pathObserver


import 'package:ortho_quant_md/widgets/measurement_boxes.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MeasurementScreen extends StatefulWidget {
  final String imagePath;
  final MeasurementRecord? initialRecord;
  const MeasurementScreen({super.key, required this.imagePath, this.initialRecord});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> with TickerProviderStateMixin {
  
  final TransformationController _transformationController = TransformationController();
  Matrix4? _preSmartZoomMatrix;
  Timer? _smartZoomTimer;

  final List<MeasurementModel> _measurements = [];
  String? _selectedMeasurementId; // ID of the currently active/selected measurement
  
  // Persistence
  late MeasurementRecord _currentRecord;
  final HistoryService _historyService = HistoryService();
  final Uuid _uuid = const Uuid();

  // Temporary state for creating a NEW measurement
  MeasurementType _currentToolType = MeasurementType.angle3Point;
  
  // Scroll Controller for measurement list
  final ScrollController _listScrollController = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = false;

  // Template State
  MeasurementTemplate? _activeTemplate;
  MeasurementTemplateBase? _activeModularTemplate; // NEW: For modular templates
  List<String> _modularResults = []; // NEW: Stores calculated results for modular templates
  int _activeLandmarkIndex = 0; // Tracks which landmark we are currently asking for
  final Map<String, String> _templateLandmarkMeasurementIds = {}; // landmarkId -> measurementId
  final Map<String, String> _templateCalculationIds = {}; // calculationId -> measurementId
  // The user sees 'Landmarks' as points. We store them as MeasurementType.point with isLandmark=true.

  final GlobalKey _captureKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey(); // Key for coordinate conversion
  final GlobalKey _rootStackKey = GlobalKey(); // To measure screen size for export scaling
  
  // Tutorial Keys
  final GlobalKey _calibBtnKey = GlobalKey();

  // final GlobalKey _saveBtnKey = GlobalKey(); // Removed
  // final GlobalKey _exportBtnKey = GlobalKey(); // Removed
  final GlobalKey _headerActionsKey = GlobalKey(); // Combined Save/Export
  final GlobalKey _menuKey = GlobalKey(); // Bottom Menu
  final GlobalKey _backBtnKey = GlobalKey();
  late TutorialCoachMark tutorialCoachMark;
  Size? _imageSize; // Loaded asynchronously
  
  // Magnifier State
  Offset? _magnifierPosition; // Local coordinate in _viewportKey stack
  
  // Style Prefs
  bool _textBold = false;
  double _textSize = 16.0;
  double _lineThickness = 2.0;
  bool _autoZoomEnabled = true;
  
  // Animations

  
  // Feedback State
  Offset _calibBtnOffset = const Offset(16, 200); // Default Position (Right, Bottom)
  

  // Template Menu State
  bool _isMenuOpen = false;
  JointCategory? _selectedCategory;
  Offset? _infoBoxPosition; // Null initially (use default), then stores user drag position




  @override
  void initState() {
    super.initState();
    debugPrint("DEBUG: templates count: ${appTemplates.length}");
    debugPrint("DEBUG: last template: ${appTemplates.last.title} (${appTemplates.last.category})");
    if (widget.initialRecord != null) {
      _currentRecord = widget.initialRecord!;
      _measurements.addAll(_currentRecord.measurements);
    } else {
      // New Session
      _currentRecord = MeasurementRecord(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        imagePath: widget.imagePath,
        measurements: _measurements,
      );
    }

    // RESTORE ACTIVE TEMPLATE IF SAVED
    if (_currentRecord.templateId != null) {
        try {
           final t = appTemplates.firstWhere((x) => x.id == _currentRecord.templateId);
           // Post-frame to ensure measurements are fully loaded? They are loaded synchronously above.
           // But setState needs to be safe.
           WidgetsBinding.instance.addPostFrameCallback((_) {
              _restoreTemplateState(t);
           });
        } catch (e) {
           debugPrint('Failed to restore template: $e');
        }
    }

    // Load initial styles
    _loadSettings();
    
    // Init Animations


    SettingsService().addListener(_onSettingsChanged);
    _persistImage(); // Ensure image is saved to permanent storage
    _loadImage();
    
    _listScrollController.addListener(_updateScrollArrows);

    // Check Tutorial
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShowTutorial());
  }

  Future<void> _persistImage() async {
     try {
        final file = File(widget.imagePath);
        if (!await file.exists()) return;
        
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = widget.imagePath.split('/').last;
        final persistentPath = '${appDir.path}/$fileName';
        
        // If already in appDir, update record and return
        if (widget.imagePath.startsWith(appDir.path)) {
           _currentRecord.imagePath = widget.imagePath;
           return;
        }
        
        // Check if we already copied it (to avoid overwriting or duplicates)
        final targetFile = File(persistentPath);
        if (!await targetFile.exists()) {
           await file.copy(persistentPath);
           print('Image persisted to: $persistentPath');
        } else {
           // File exists in documents, use it
        }
        
        setState(() {
           _currentRecord.imagePath = persistentPath;
        });
        
        // Save the record with the new persistent path
        await _historyService.saveRecord(_currentRecord);
        
     } catch (e) {
        print('Error persisting image: $e');
     }
  }

  Future<void> _loadImage() async {
    try {
      final file = File(_currentRecord.imagePath); // Use record path (likely persisted)
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        setState(() {
          _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        });
        
        // Ensure template outputs are generated if a template was restored before image load
        _generateTemplateOutputs();
      } else {
        print("Image not found at ${_currentRecord.imagePath}");
      }
    } catch (e) {
      print("Error loading image: $e");
    }
  }
  
  void _onSettingsChanged() {
    _loadSettings();
  }

  Future<void> _checkAndShowTutorial() async {
      final prefs = await SharedPreferences.getInstance();
      // Using v2 to force show revised tutorial
      final shown = prefs.getBool('measurement_tutorial_shown_v2') ?? false;
      if (!shown) {
          Future.delayed(const Duration(milliseconds: 500), () {
             _createTutorial();
             if (mounted) tutorialCoachMark.show(context: context);
          });
          prefs.setBool('measurement_tutorial_shown_v2', true);
      }
    }

  void _handleDoubleTap(TapDownDetails details, Rect imageRect) {
    if (_imageSize == null) return;
    
    // 1. If active measurement has points, zoom to fit it
    if (_selectedMeasurementId != null) {
      final _activeMeasurement = _measurements.firstWhere((m) => m.id == _selectedMeasurementId);
      if (_activeMeasurement.points.isNotEmpty) {
        final bounds = GeometryUtils.calculateBoundingBox(_activeMeasurement.points.map((p) => p.position).toList());
        if (bounds != null) {
          // Add padding (20%)
          final center = bounds.center;
          // Calculate scale to fit. 
          // Simplified: Zoom to 3x at center of measurement or 1.0 depending on current
          final currentScale = _transformationController.value.getMaxScaleOnAxis();
          final targetScale = currentScale < 2.0 ? 3.0 : 1.0;
          
          _animateZoom(
             targetScale, 
             _denormalizePoint(center, imageRect) // Zoom target in screen pixels
          );
          return;
        }
      }
    }
    
    // 2. Default: Zoom in/out at tap position
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = currentScale < 2.0 ? 2.5 : 1.0;
    
    // Tap position is in local coordinate space of the viewport
    // Use details.localPosition directly? InteractiveViewer child is the image.
    // details.localPosition is relative to the widget handling the tap (GestureDetector inside Viewer)
    _animateZoom(targetScale, details.localPosition);
  }

  void _animateMatrix(Matrix4 targetMatrix) {
    if (_imageSize == null) return;
    
    final currentMatrix = _transformationController.value;
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    final zoomAnim = Matrix4Tween(begin: currentMatrix, end: targetMatrix).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    
    zoomAnim.addListener(() {
      _transformationController.value = zoomAnim.value;
    });
    
    controller.forward().then((_) => controller.dispose());
  }

  void _animateZoom(double targetScale, Offset focusPoint) {
      if (_imageSize == null) return;
      
      final currentMatrix = _transformationController.value;
      final currentScale = currentMatrix.getMaxScaleOnAxis();
      
      // Calculate translation to keep focusPoint centered
      // Matrix: [scale, 0, 0, tx]
      //         [0, scale, 0, ty]
      
      // We want focusPoint to be at the center of the viewport (or keep its relative position?)
      // Standard double-tap zoom usually centers theタップ point.
      
      // Viewport Center
      final viewportSize = _viewportKey.currentContext?.size ?? Size.zero;
      final viewCenter = viewportSize.center(Offset.zero);
      
      // Target Matrix Construction
      final targetMatrix = Matrix4.identity()
        ..translate(viewCenter.dx, viewCenter.dy)
        ..scale(targetScale)
        ..translate(-focusPoint.dx, -focusPoint.dy);
        
      // Animate
      // Create a temporary controller for zoom
      final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
      final zoomAnim = Matrix4Tween(begin: currentMatrix, end: targetMatrix).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
      
      zoomAnim.addListener(() {
        _transformationController.value = zoomAnim.value;
      });
      
      controller.forward().then((_) => controller.dispose());
  }

  void _createTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: _createTargets(),
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 5,
      opacityShadow: 0.85,
    );
  }

  List<TargetFocus> _createTargets() {
    List<TargetFocus> targets = [];

    // 1. Calibration (Most Important)
    targets.add(
      TargetFocus(
        identify: "Calibration",
        keyTarget: _calibBtnKey,
        alignSkip: Alignment.topLeft,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text(
                    "Calibrate First",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                  ),
                   SizedBox(height: 10),
                   Text(
                    "For accurate measurements (mm), mark a known distance (like a marker ball) using this tool.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.right,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 2. Select Tool (Bottom Menu)
    targets.add(
      TargetFocus(
        identify: "SelectTool",
        keyTarget: _menuKey,
        alignSkip: Alignment.topRight,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                   Text(
                    "Select Tool",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                  ),
                   SizedBox(height: 10),
                   Text(
                    "Choose Angle, Cobb, Distance or other tools from here.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    // 4. Save & Share (Combined)
    targets.add(
      TargetFocus(
        identify: "SaveShare",
        keyTarget: _headerActionsKey,
        alignSkip: Alignment.bottomLeft,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text(
                    "Save & Share",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                  ),
                   SizedBox(height: 10),
                   Text(
                    "Save your work to History or export the image to Gallery/PDF.",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.right,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );

    return targets;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _openInfoDialog() {
    if (_activeTemplate == null || _activeTemplate!.infoDescription == null) return;
    
    MeasurementInfoDialog.show(context, _activeTemplate!.title, _activeTemplate!.infoDescription!);

  }



  @override
  void dispose() {
    SettingsService().removeListener(_onSettingsChanged);
    _autoSave();
    _listScrollController.removeListener(_updateScrollArrows);
    _listScrollController.dispose();
    _transformationController.dispose();

    super.dispose();
  }



  Future<void> _autoSave() async {
    // Sync current measurements to the record
    // Sync current measurements to the record
    _currentRecord.measurements = List.from(_measurements);
    if (_activeTemplate != null) {
       _currentRecord.templateId = _activeTemplate!.id;
    }

    // Only save if we have measurements or if it was already saved manually
    if (_measurements.isNotEmpty || !_currentRecord.isAutoSaved) {
       await _historyService.saveRecord(_currentRecord);
    }
  }

  Future<void> _openSaveScreen() async {
    await _autoSave(); // Save current state first
    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SaveRecordScreen(record: _currentRecord))
    );
    
    if (result == true) {
      if (mounted) _showSuccessAnimation("Record saved successfully.");
    }
  }

  void _showSuccessAnimation(String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return SuccessOverlay(message: message);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      }
    );
  }

  void _updateScrollArrows() {
    if (!_listScrollController.hasClients) return;
    final maxScroll = _listScrollController.position.maxScrollExtent;
    final currentScroll = _listScrollController.offset;
    
    setState(() {
      _showLeftArrow = currentScroll > 5;
      _showRightArrow = currentScroll < maxScroll - 5;
    });
  }




  Rect _calculateImageRect(Size containerSize) {
    if (_imageSize == null) return Rect.zero;
    
    final wRatio = containerSize.width / _imageSize!.width;
    final hRatio = containerSize.height / _imageSize!.height;
    final scale = wRatio < hRatio ? wRatio : hRatio;
    
    final drawW = _imageSize!.width * scale;
    final drawH = _imageSize!.height * scale;
    
    final dx = (containerSize.width - drawW) / 2;
    final dy = (containerSize.height - drawH) / 2;
    
    return Rect.fromLTWH(dx, dy, drawW, drawH);
  }

  Offset _normalizePoint(Offset localPos, Rect imageRect) {
    // Convert screen pixel to 0..1 relative to imageRect
    if (imageRect.isEmpty) return Offset.zero;
    final dx = (localPos.dx - imageRect.left) / imageRect.width;
    final dy = (localPos.dy - imageRect.top) / imageRect.height;
    return Offset(dx, dy);
  }

  Offset _denormalizePoint(Offset normPos, Rect imageRect) {
    // Convert 0..1 to screen pixel
    if (imageRect.isEmpty) return Offset.zero;
    return Offset(
      imageRect.left + normPos.dx * imageRect.width, 
      imageRect.top + normPos.dy * imageRect.height
    );
  }
  
  double? _calculatePxPerMm(Rect imageRect) {
     try {
       final calib = _measurements.firstWhere((m) => m.type == MeasurementType.calibration);
       if (calib.points.length >= 2 && calib.calibrationValue != null && calib.calibrationValue! > 0) {
          final p1 = _denormalizePoint(calib.points[0].position, imageRect);
          final p2 = _denormalizePoint(calib.points[1].position, imageRect);
          return (p1 - p2).distance / calib.calibrationValue!;
       }
     } catch (_) {}
     return null;
  }

  // Check if calibration exists
  bool get _hasCalibration => _measurements.any((m) => m.type == MeasurementType.calibration);

  MeasurementModel? get _activeMeasurement {
    if (_selectedMeasurementId == null) return null;
    try {
      return _measurements.firstWhere((m) => m.id == _selectedMeasurementId);
    } catch (e) {
      return null;
    }
  }

  final List<Color> _availableColors = [
    const Color(0xFF00BFA5), // Teal
    const Color(0xFFFF4081), // Pink
    const Color(0xFF2979FF), // Blue

    const Color(0xFFB388FF), // Purple
    const Color(0xFF76FF03), // Light Green
    const Color(0xFFFF6E40), // Deep Orange
    const Color(0xFF18FFFF), // Cyan Accent
  ];

  Color _getNextColor() {
    if (_measurements.isEmpty) return _availableColors[0];
    final usedColors = _measurements.map((m) => m.color).toSet();
    for (final color in _availableColors) {
      if (!usedColors.contains(color)) return color;
    }
    return _availableColors[math.Random().nextInt(_availableColors.length)];
  }

  void _createNewMeasurement(MeasurementType type, {String? label, List<ReferencePoint>? initialPoints, bool forceAcute = false, List<String>? sourceIds}) {
    // If trying to add calibration but one exists (should be blocked by UI, but safe guard)
    if (type == MeasurementType.calibration && _hasCalibration) return;
    
    // Prevent multiple incomplete measurements of same type (outside Template only)
    if (_activeTemplate == null) {
        final hasIncomplete = _measurements.any((m) => m.type == type && m.points.length < m.totalSteps);
        if (hasIncomplete) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete the current measurement first.')));
            return;
        }
    }
    
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Calculate initial active step if points provided
    int startStep = 1;
    if (initialPoints != null && initialPoints.isNotEmpty) {
       startStep = initialPoints.length + 1;
    }

    setState(() {
      _selectedMeasurementId = newId;
      _currentToolType = type;
      _measurements.add(MeasurementModel(
        id: newId, 
        type: type,
        color: type == MeasurementType.calibration ? Colors.white : _getNextColor(), // White for calibration
        activeStep: startStep,
        totalSteps: (type == MeasurementType.spinopelvic || type == MeasurementType.lcea) ? 6 : 
                    (type == MeasurementType.pelvicTilt || type == MeasurementType.pelvicIncidence || type == MeasurementType.cobbAngle || type == MeasurementType.blackburnePeel || type == MeasurementType.glenoidDefect || type == MeasurementType.tonnisAngle) ? 4 : 
                    (type == MeasurementType.modifiedInsallSalvati || type == MeasurementType.angle3Point || type == MeasurementType.circle3Point) ? 3 : 
                    (type == MeasurementType.point) ? 1 :
                    (type == MeasurementType.areaPolygon) ? 99 : // Dynamic polygon, finish button required
                    (type == MeasurementType.distance || type == MeasurementType.calibration || type == MeasurementType.circle || type == MeasurementType.sacralSlope || type == MeasurementType.areaCircle) ? 2 : 1,
        label: label,
        forceAcute: forceAcute,
        points: initialPoints, // Can be null
        sourceIds: sourceIds, 
        isAuxiliary: type == MeasurementType.glenoidDefect, // Auto-hide Glenoid Result
      ));
      

    });
  }
  
  void _duplicateMeasurement() {
    if (_activeMeasurement != null && _activeMeasurement!.type != MeasurementType.calibration) {
      setState(() {
        final clone = _activeMeasurement!.clone();
        // Shift clone slightly so it's visible (Normalized offset approx 5%)
        final offset = const Offset(0.05, 0.05);
        final offsetPoints = clone.points.map((p) => ReferencePoint(p.position + offset, label: p.label)).toList();
        clone.points = offsetPoints;
        clone.color = _getNextColor(); // Assign new color to duplicate
        if (clone.labelPosition != null) {
           clone.labelPosition = clone.labelPosition! + offset;
        }
        _measurements.add(clone);
        _selectedMeasurementId = clone.id; // Select the new one
      });
    }
  }

  void _handleTapUp(TapUpDetails details, Rect imageRect) {
    if (_isMenuOpen) {
       _elementTapped();
       return;
    }

    if (_selectedMeasurementId == null) {
       _trySelectObject(details.localPosition, imageRect);
       return; 
    }

    final activeMeasure = _activeMeasurement;
    if (activeMeasure == null) return;

    if (activeMeasure.isLocked) {
       bool found = _trySelectObject(details.localPosition, imageRect);
       if (!found) {
          setState(() {
            _selectedMeasurementId = null;
          });
       }
       return;
    }

    int limit = 99;
    if (activeMeasure.type == MeasurementType.spinopelvic || activeMeasure.type == MeasurementType.lcea) limit = 6;
    if (activeMeasure.type == MeasurementType.angle3Point) limit = 3;
    if (activeMeasure.type == MeasurementType.cobbAngle || activeMeasure.type == MeasurementType.pelvicTilt || activeMeasure.type == MeasurementType.pelvicIncidence || activeMeasure.type == MeasurementType.blackburnePeel || activeMeasure.type == MeasurementType.glenoidDefect || activeMeasure.type == MeasurementType.tonnisAngle) limit = 4;
    if (activeMeasure.type == MeasurementType.modifiedInsallSalvati || activeMeasure.type == MeasurementType.circle3Point) limit = 3;
    if (activeMeasure.type == MeasurementType.point) limit = 1;
    // Circle, Distance, Calibration all need 2 points
    if (activeMeasure.type == MeasurementType.distance || activeMeasure.type == MeasurementType.calibration || activeMeasure.type == MeasurementType.circle || activeMeasure.type == MeasurementType.sacralSlope || activeMeasure.type == MeasurementType.areaCircle) limit = 2;
    if (activeMeasure.type == MeasurementType.areaPolygon) limit = 99; // Dynamic, controlled by finish button

    if (activeMeasure.points.length >= limit) {
       bool found = _trySelectObject(details.localPosition, imageRect);
       if (!found) {
          setState(() {
            _selectedMeasurementId = null;
          });
       }
      return;
    }

    setState(() {
      // Normalize before adding
      activeMeasure.points.add(ReferencePoint(
        _normalizePoint(details.localPosition, imageRect),
        label: activeMeasure.label ?? ''
      ));
      // Update Step
      if (activeMeasure.points.length < activeMeasure.totalSteps) {
         activeMeasure.activeStep = activeMeasure.points.length + 1;
      } else {
         activeMeasure.activeStep = activeMeasure.totalSteps;
         // Auto-deselect if complete (except calibration)
         if (activeMeasure.type != MeasurementType.calibration) {
            // _selectedMeasurementId = null; // Removed auto-deselect on finish per new logic preference, or keep? 
            // User asked: "Eğer çizim yapmıyorsam... boş bir noktaya tıkladığımda... iptal olsun"
            // So if I finish drawing, I am still selected. Then I tap empty -> deselect.
            // If I auto-deselect here, the user won't have a chance to see it selected.
            // But standard behavior usually implies finished = active.
            // I'll keep it active so they can adjust immediately if needed.
            // So I REMOVE the auto-deselect here.
         }
      }
      

      
      // Auto-trigger dialog for calibration
      if (activeMeasure.type == MeasurementType.calibration && activeMeasure.points.length == 2 && activeMeasure.calibrationValue == null) {
          _showCalibrationDialog();
      }
      

             
       // AUTO-ADVANCE LANDMARKS
       if (_activeTemplate != null && _activeMeasurement != null) {
          // Skip landmark auto-advance for areaPolygon (user controls via finish button)
          if (_activeMeasurement!.type == MeasurementType.areaPolygon) {
            // Don't auto-advance, let user keep adding points
            // Finish button will handle completion
           } else if (_activeMeasurement!.points.length >= 1) { // Landmarks are always single points currently
              if (_activeLandmarkIndex < _activeTemplate!.landmarks.length - 1) {
                 _activeLandmarkIndex++;
                 final nextLm = _activeTemplate!.landmarks[_activeLandmarkIndex];
                 _createNewMeasurement(MeasurementType.point, label: nextLm.label);
                 if (_selectedMeasurementId != null) {
                     _templateLandmarkMeasurementIds[nextLm.id] = _selectedMeasurementId!;
                 }
                 // Check for intermediate outputs
                 _checkIntermediateTemplateCalculations();
              } else if (_activeLandmarkIndex == _activeTemplate!.landmarks.length - 1) {
                  // Finished Inputs
                  // Mark as finished ONLY ONCE
                  _activeLandmarkIndex = _activeTemplate!.landmarks.length; // Indicating Done Input
                  
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_activeTemplate!.title} Landmarks Placed!')));
                  // Generate Output Layer
                  _generateTemplateOutputs();
                  
                  // Deselect the last point so user can see the whole picture or select others
                  _selectedMeasurementId = null;
              }
           }
       }
     });
   }
   
   void _generateTemplateOutputs() {
      // MODULAR TEMPLATE LOGIC
      if (_activeModularTemplate != null && _imageSize != null) {
          // 1. Gather all points that are 'point' type (landmarks)
           List<ReferencePoint> landmarks = [];
           for (final m in _measurements) {
               if (m.type == MeasurementType.point) {
                   landmarks.addAll(m.points);
               }
           }
           
           // 2. Calculate
           final fullImageRect = Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height);
           final pixelsPerMm = _calculatePxPerMm(fullImageRect);
           final results = _activeModularTemplate!.calculate(landmarks, fullImageRect, pixelsPerMm: pixelsPerMm);
           
           // 3. Save Results (Will be displayed by TemplateResultBox)
           if (results.isNotEmpty) {
               setState(() {
                   _modularResults = results;
               });
           }
           return;
      }

      _syncTemplateMeasurements();
   }
   bool _trySelectObject(Offset position, Rect imageRect) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final double threshold = 40.0 / scale; // Target 40 logical pixels on screen (easier touch)

    String? bestMId;
    double minDistance = double.infinity;

    // 1. Try selecting the CLOSEST Point
    for (final m in _measurements) {
      if (m.isAuxiliary || m.isTemplateResult) continue;
      if (m.type == MeasurementType.pelvicTilt || m.type == MeasurementType.pelvicIncidence) continue;

      for (final p in m.points) {
        final screenPos = _denormalizePoint(p.position, imageRect);
        final dist = (screenPos - position).distance;
        
        // If within threshold and closer than previously found candidate
        // Note: Using <= ensures if multiple points are at same pos, the one later in list (higher Z) can be picked 
        if (dist < threshold && dist <= minDistance) {
           minDistance = dist;
           bestMId = m.id;
        }
      }
    }

    if (bestMId != null) {
       setState(() {
         _selectedMeasurementId = bestMId;
       });
       return true;
    }
    
    // 2. Try selecting a Label
    // 2. Try selecting a Label
    for (final m in _measurements) {
       Offset? checkPos;
       
       if (m.labelPosition != null) {
          checkPos = _denormalizePoint(m.labelPosition!, imageRect);
       } else {
          // Calculate Default Position (Same logic as Painter)
          final pts = m.points.map((p) => _denormalizePoint(p.position, imageRect)).toList();
          if (pts.isEmpty) continue;

          if (m.type == MeasurementType.sacralSlope && pts.length >= 2) {
             final s1Center = (pts[0] + pts[1]) / 2;
             checkPos = s1Center + const Offset(10, -30);
          } else if (m.type == MeasurementType.pelvicTilt && pts.length >= 4) {
             final hipCenter = (pts[2] + pts[3]) / 2;
             checkPos = hipCenter + const Offset(10, -50);
          } else if (m.type == MeasurementType.pelvicIncidence && pts.length >= 4) {
             final s1Center = (pts[0] + pts[1]) / 2;
             checkPos = s1Center + const Offset(10, 30);
          } else if (m.type == MeasurementType.cobbAngle && pts.length >= 4) {
             checkPos = (pts[0] + pts[1] + pts[2] + pts[3]) / 4;
          } else if (m.type == MeasurementType.angle3Point && pts.length >= 3) {
             checkPos = pts[1] + const Offset(15, -30);
          } else if ((m.type == MeasurementType.distance || m.type == MeasurementType.calibration || m.type == MeasurementType.circle || m.type == MeasurementType.point) && pts.length >= 1) {
             // Default for simple types
             final center = pts.length == 1 ? pts[0] : (pts[0] + pts[1]) / 2;
             checkPos = center + const Offset(10, -30);
          } else if (m.type == MeasurementType.circle3Point && pts.length >= 3) {
             final res = GeometryUtils.calculateCircleFrom3Points(pts[0], pts[1], pts[2]);
             if (res != null) {
                checkPos = res['center'] + const Offset(10, -30);
             }
          } else if (m.type == MeasurementType.modifiedInsallSalvati && pts.length >= 2) {
             // Near Patella Inferior
             checkPos = pts[1] + const Offset(20, 0); 
          } else if (m.type == MeasurementType.blackburnePeel && pts.length >= 2) {
             // Near Patella Inferior
             checkPos = pts[1] + const Offset(20, 20);
          }
       }

       if (checkPos != null) {
          final rect = Rect.fromLTWH(checkPos.dx, checkPos.dy, 80, 40); // Slightly larger touch area
          if (rect.contains(position)) {
             setState(() {
               _selectedMeasurementId = m.id;
               // If it was null (default), set it now so we can drag it
               if (m.labelPosition == null) {
                   m.labelPosition = _normalizePoint(checkPos!, imageRect);
               }
             });
             return true;
          }
       }
       }
    return false;
  }

   bool _checkIntermediateTemplateCalculations() {
     return _syncTemplateMeasurements();
   }

  void _showCalibrationDialog() {
    // 1. Check if calibration exists
    MeasurementModel? m;
    try {
        m = _measurements.firstWhere((m) => m.type == MeasurementType.calibration);
    } catch (_) {}

    // 2. If NOT exists, create it now!
    if (m == null) {
        _createNewMeasurement(MeasurementType.calibration);
        // Wait for next frame/state update or just inform user
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Draw a line on a known length (e.g. marker ball)."), duration: Duration(seconds: 2)));
        return; 
    }

    // 3. If exists but points are incomplete, select it
    if (m.points.length < 2) {
         setState(() { _selectedMeasurementId = m!.id; });
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Finish drawing the calibration line first."), duration: Duration(seconds: 2)));
         return;
    }

    // 4. If exists and complete, show input dialog
    final controller = TextEditingController(text: m.calibrationValue?.toString() ?? '');

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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                setState(() {
                  m!.calibrationValue = val;
                  // Trigger recalculation immediately to update mm values
                  _generateTemplateOutputs();
                });
                _autoSave();
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _undoPoint() {
    final m = _activeMeasurement;
    if (m != null && m.points.isNotEmpty && !m.isLocked) {
      setState(() {
        m.points.removeLast();
        // Update Step
        if (m.points.isEmpty) {
           m.activeStep = 1;
        } else {
           m.activeStep = m.points.length + 1;
        }
      });
    }
  }

   void _deleteMeasurement() {
    if (_selectedMeasurementId != null) {
      // Check if this ID is part of active template
      if (_activeTemplate != null) {
         bool isTemplateItem = _templateLandmarkMeasurementIds.containsValue(_selectedMeasurementId) || 
                               _templateCalculationIds.containsValue(_selectedMeasurementId);
         
         if (isTemplateItem) {
             // Delete ALL template items
             setState(() {
                 // Remove Landmarks
                 for (var id in _templateLandmarkMeasurementIds.values) {
                     _measurements.removeWhere((m) => m.id == id);
                 }
                 // Remove Calculations
                 for (var id in _templateCalculationIds.values) {
                     _measurements.removeWhere((m) => m.id == id);
                 }
                 
                 _templateLandmarkMeasurementIds.clear();
                 _templateCalculationIds.clear();
                 _activeTemplate = null;
                 _selectedMeasurementId = null;
                 _activeLandmarkIndex = 0;
             });
             return; // Done
         }
      }
    
      setState(() {
        _measurements.removeWhere((m) => m.id == _selectedMeasurementId);
        _selectedMeasurementId = null;
      });
    }
  }

  void _toggleLock() {
    if (_activeMeasurement != null) {
      setState(() {
        _activeMeasurement!.isLocked = !_activeMeasurement!.isLocked;
      });
    }
  }

  void _finishPolygon() {
    if (_activeMeasurement != null && _activeMeasurement!.type == MeasurementType.areaPolygon) {
      if (_activeMeasurement!.points.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Polygon needs at least 3 points'))
        );
        return;
      }
      
      setState(() {
        _activeMeasurement!.isLocked = true;
        _selectedMeasurementId = null; // Deselect after finishing
      });
    }
  }

  void _updateMagnifier(Offset globalPos) {
      final RenderBox? box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        setState(() {
          _magnifierPosition = box.globalToLocal(globalPos);
        });
      }
  }

  void _updateMagnifierFromLocalPoint(Offset localPos) {
      final RenderBox? box = _captureKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
         final globalPos = box.localToGlobal(localPos);
         _updateMagnifier(globalPos);
      }
  }

  void _hideMagnifier() {
    setState(() {
      _magnifierPosition = null;
    });
  }

  Future<void> _loadSettings() async {
    // Read directly from cached service
    if (mounted) {
      setState(() {
        _textBold = SettingsService().textBold;
        _textSize = SettingsService().textSize;
        _lineThickness = SettingsService().lineThickness;
        _autoZoomEnabled = SettingsService().autoZoomEnabled;
      });
      // Banner removed per user request
    }
  }

  Future<void> _openSettings() async {
     Navigator.push(
       context,
       MaterialPageRoute(builder: (context) => const SettingsScreen()),
     );
  }

   void _restoreTemplateState(MeasurementTemplate template) {
     setState(() {
        _activeTemplate = template;
        _activeModularTemplate = TemplateRegistry.getById(template.id);
        _modularResults.clear();
        _activeLandmarkIndex = template.landmarks.length; // Assume complete
        _templateLandmarkMeasurementIds.clear();
        _templateCalculationIds.clear();

        // 1. Restore Landmark Mappings
        for (var lm in template.landmarks) {
           try {
              // Find measurement with matching label
              final m = _measurements.firstWhere((x) => x.type == MeasurementType.point && x.label == lm.label);
              _templateLandmarkMeasurementIds[lm.id] = m.id;
           } catch (_) {}
        }

        // 2. Restore Calculation Mappings
        for (var calc in template.calculations) {
           try {
              // Priority 1: Match by label
              // Priority 2: Match by type (if only one exists)
              final mCandidates = _measurements.where((x) => x.label == calc.label).toList();
              if (mCandidates.isNotEmpty) {
                 _templateCalculationIds[calc.id] = mCandidates.first.id;
              } else {
                 // Try type match only if unique? 
                 // For complex templates like RSA, we rely on labels as defined in create-logic.
                 final mTypeCandidates = _measurements.where((x) => x.type == calc.type && x.isAuxiliary == calc.isAuxiliary).toList();
                 if (mTypeCandidates.length == 1) {
                    _templateCalculationIds[calc.id] = mTypeCandidates.first.id;
                 }
              }
           } catch (_) {}
        }
        
        // Specific Fix for Glenoid Defect 
        if (template.id == 'glenoid_bone_loss') {
            try {
               final m = _measurements.firstWhere((x) => x.type == MeasurementType.glenoidDefect);
               _templateCalculationIds['gbl_percent'] = m.id;
               _templateCalculationIds['gbl_size'] = m.id;
            } catch (_) {}
        }
        
        // Specific Fix for Glenoid Version
        if (template.id == 'glenoid_version') {
            try {
               final m = _measurements.firstWhere((x) => x.type == MeasurementType.glenoidVersion);
               for (var c in template.calculations) {
                    _templateCalculationIds[c.id] = m.id;
               }
            } catch (_) {}
        }

        // Refresh calculations to ensure Point X etc. are synchronized
        _syncTemplateMeasurements();
        _generateTemplateOutputs();
     });
   }

   bool _syncTemplateMeasurements() {
      if (_activeTemplate == null) return false;
      bool changed = false;

      // Ensure we have all landmarks properly mapped and updated
      for (final calc in _activeTemplate!.calculations) {
          // 1. Gather points from landmarks
          final List<ReferencePoint> points = [];
          bool missing = false;
          for (final lmId in calc.landmarkIds) {
              final mId = _templateLandmarkMeasurementIds[lmId];
              if (mId == null) { missing = true; break; }
              final landmarkM = _measurements.firstWhere((x) => x.id == mId, orElse: () => MeasurementModel(id: '', type: MeasurementType.point, points: [], color: Colors.black, activeStep: 1, totalSteps: 1));
              if (landmarkM.points.isEmpty) { missing = true; break; }
              points.add(landmarkM.points.first);
          }
          
          if (missing) continue;

          // 2. Find or Create the Calculation Measurement
          final existingId = _templateCalculationIds[calc.id];
          MeasurementModel? m;
          if (existingId != null) {
              m = _measurements.firstWhere((x) => x.id == existingId, orElse: () => MeasurementModel(id: '', type: MeasurementType.point, points: [], color: Colors.transparent, activeStep: 1, totalSteps: 1));
              if (m.id == '') m = null;
          }

          bool isNew = false;
          if (m == null) {
              final newId = DateTime.now().millisecondsSinceEpoch.toString() + calc.id;
              m = MeasurementModel(
                id: newId,
                type: calc.type,
                color: Colors.yellowAccent,
                activeStep: points.length,
                totalSteps: points.length,
                points: List.from(points),
                label: calc.label,
                forceAcute: calc.forceAcute,
                isLocked: false, // Per User Request: Should NOT start locked
                isAuxiliary: calc.isAuxiliary,
                isTemplateResult: true, // Mark so we can hide points
              );
              _templateCalculationIds[calc.id] = newId;
              isNew = true;
          }

          // 3. Update Points & Custom Logic
          m.points = List.from(points);
          
          // Apply Custom Logic for Glenoid Planning (AP)
          if (_activeTemplate!.id == 'glenoid_planning_ap') {
              if (calc.id == 'ss_fossa_line') {
                  m.isDashed = true;
                  m.isInfinite = true;
                  m.color = Colors.cyanAccent;
              } else if (calc.id == 'perp_c_line' || calc.id == 'rsa' || calc.id == 'asa') {
                  final aId = _templateLandmarkMeasurementIds['ss_med'];
                  final bId = _templateLandmarkMeasurementIds['ss_lat'];
                  final cId = _templateLandmarkMeasurementIds['gl_inf'];
                  
                  if (aId != null && bId != null && cId != null) {
                      final pA = _measurements.firstWhere((x) => x.id == aId).points.first.position;
                      final pB = _measurements.firstWhere((x) => x.id == bId).points.first.position;
                      final pC = _measurements.firstWhere((x) => x.id == cId).points.first.position;
                      
                      final pX = GeometryUtils.projectPointToLine(pC, pA, pB);
                      
                      if (calc.id == 'perp_c_line') {
                          m.points = [ReferencePoint(pX), ReferencePoint(pC)];
                          m.isDashed = true;
                          m.isInfinite = true;
                          m.color = Colors.cyanAccent;
                      } else if (calc.id == 'rsa' || calc.id == 'asa') {
                          // Replace index 0 (ss_med) with point X
                          if (m.points.isNotEmpty) {
                            m.points[0] = ReferencePoint(pX);
                          }
                      }
                  }
              }
          }

          if (isNew) {
              _measurements.add(m);
              changed = true;
          }
      }
      return changed;
   }

  Future<void> _startTemplate(MeasurementTemplate template) async {
      if (_activeTemplate != null) {
          if (_activeTemplate!.id == template.id) return; // Same template, do nothing

          final bool? confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace Active Template?'),
              content: const Text('Only one active template is allowed. Do you want to replace the current template and clear its measurements?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace'),
                ),
              ],
            ),
          );

          if (confirm != true) return;
          
          // Clear associated measurements of the OLD template
          setState(() {
             final idsToRemove = <String>{
                ..._templateLandmarkMeasurementIds.values,
                ..._templateCalculationIds.values
             };
             _measurements.removeWhere((m) => idsToRemove.contains(m.id));
             _activeTemplate = null; 
          });
      }
      
      _activateTemplate(template);
  }

  void _activateTemplate(MeasurementTemplate template) {
      if (template.landmarks.isEmpty) return;
      
      setState(() {
         // Standard Flow
         _activeTemplate = template;
         _activeModularTemplate = TemplateRegistry.getById(template.id);
         _modularResults.clear();
         _activeLandmarkIndex = 0;
         _templateLandmarkMeasurementIds.clear(); 
         _templateCalculationIds.clear(); 
         
         // Start first landmark
         final lm = template.landmarks.first;
         _createNewMeasurement(MeasurementType.point, label: lm.label); 
         
         if (_selectedMeasurementId != null) {
             _templateLandmarkMeasurementIds[lm.id] = _selectedMeasurementId!;
         }
      });
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      if (!_isMenuOpen) _selectedCategory = null;
    });
  }

  void _elementTapped() {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
        _selectedCategory = null;
      });
    }
  }

  Widget _buildTemplateMenuOverlay() {
    if (!_isMenuOpen) return const SizedBox.shrink();

    final displayedCategories = [
      JointCategory.shoulder,
      JointCategory.elbow,
      JointCategory.hand,
      JointCategory.spine,
      JointCategory.hip,
      JointCategory.knee,
      JointCategory.foot,
      JointCategory.other
    ];

    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    return Stack(
      children: [
        // DIMMER BACKGROUND (Tapping here closes menu)
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleMenu,
            child: Container(color: Colors.transparent),
          ),
        ),

        // THE TEMPLATE LIST PANEL (Appears to the left of icons)
        if (_selectedCategory != null)
          Builder(builder: (context) {
            final cat = _selectedCategory!;
            final catTemplates = appTemplates.where((t) => t.category == cat).toList();
            final catIndex = displayedCategories.indexOf(cat);
            
            // Positioning logic:
            // Icons are bottom: 90. Each icon Box is 64px high.
            // Distance from bottom of screen to the center of the icon:
            final iconCenterFromBottom = (displayedCategories.length - 1 - catIndex) * 64 + 90 + 32;

            // Panel height estimation (rough)
            // Smaller items = less height per item. Let's use ~54 instead of 70.
            final panelHeight = math.min(screenHeight - 200, 20.0 + (catTemplates.length * 54.0));
            
            return Positioned(
              right: 84, // 16 margin + 56 icon + 12 gap
              // Try to center the panel vertically on the icon center
              // Safe area: bottom 100, top (screenHeight - 100)
              bottom: math.max(100.0, math.min(screenHeight - panelHeight - 110, iconCenterFromBottom - (panelHeight / 2))),
              child: ListenableBuilder(
                listenable: SubscriptionService(),
                builder: (context, _) => Container(
                  width: 260,
                  constraints: BoxConstraints(maxHeight: screenHeight - 220),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black45, blurRadius: 12, offset: const Offset(0, 4))
                    ]
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // List
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: catTemplates.isNotEmpty ? catTemplates.map((t) {
                               final isAllowed = SubscriptionService().canAccessTemplate(t.isPremium);
                               return GestureDetector(
                                 onTap: () {
                                   if (!isAllowed) {
                                     Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
                                   } else {
                                     _startTemplate(t);
                                     _toggleMenu();
                                   }
                                 },
                                 child: Container(
                                   margin: const EdgeInsets.only(bottom: 6),
                                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                   decoration: BoxDecoration(
                                     color: const Color(0xFF00BFA5).withValues(alpha: 0.05),
                                     borderRadius: BorderRadius.circular(12),
                                     border: Border.all(color: const Color(0xFF00BFA5).withValues(alpha: 0.15))
                                   ),
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                        Row(
                                         crossAxisAlignment: CrossAxisAlignment.center,
                                         children: [
                                           Expanded(
                                             child: Text(
                                               t.title, 
                                               style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                                               softWrap: true,
                                             ),
                                           ),
                                           if (t.isPremium && !SubscriptionService().isPro) ...[
                                             const SizedBox(width: 8),
                                             Container(
                                               padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                               decoration: BoxDecoration(
                                                 color: Colors.amber,
                                                 borderRadius: BorderRadius.circular(6),
                                               ),
                                               child: const Text('PRO', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                                             ),
                                           ],
                                         ],
                                       ),
                                       if (t.viewInfo.isNotEmpty)
                                         Padding(
                                           padding: const EdgeInsets.only(top: 2.0),
                                           child: Text(
                                               t.viewInfo,
                                               style: const TextStyle(
                                                 color: Colors.black54,
                                                 fontSize: 11,
                                                 fontWeight: FontWeight.w400,
                                                 fontStyle: FontStyle.italic
                                               ),
                                            ),
                                         ),
                                     ],
                                   ),
                                 ),
                               );
                            }).toList() : [
                              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text("Henüz şablon bulunmuyor", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)))
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

        // CATEGORY ICONS STRIP (Fixed Position)
        Positioned(
          bottom: 90,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: displayedCategories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return SizedBox(
                height: 64,
                width: 64,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                       setState(() {
                         if (_selectedCategory == cat) {
                           _selectedCategory = null; 
                         } else {
                           _selectedCategory = cat;
                         }
                       });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSelected ? 56 : 46,
                      height: isSelected ? 56 : 46,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00BFA5) : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))
                        ]
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ClipOval(
                        child: Image.asset(
                          cat.assetPath,
                          color: isSelected ? Colors.white : Colors.black87,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            cat.icon, 
                            color: isSelected ? Colors.white : Colors.black87, 
                            size: isSelected ? 28 : 24
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _exportImage() async {
    // Capture Image
    Uint8List? pngBytes;
    Size? displaySize;
    double? exportPxPerMm;
    
    try {
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        displaySize = boundary.paintBounds.size;
        
        // 1. Capture the UI (Canvas with points, lines, and actual image) at 2x quality
        final uiImage = await boundary.toImage(pixelRatio: 2.0);
        final width = uiImage.width.toDouble();
        final height = uiImage.height.toDouble();

        // 2. Composting (Results Box + Watermark)
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        // Draw Base UI Capture
        canvas.drawImage(uiImage, Offset.zero, Paint());

        // Get Screen Reference Size for scaling
        final RenderBox? rootBox = _rootStackKey.currentContext?.findRenderObject() as RenderBox?;
        final rootW = rootBox?.size.width ?? MediaQuery.of(context).size.width;
        final rootH = rootBox?.size.height ?? MediaQuery.of(context).size.height;
        final double scaleFactor = width / rootW;

        // A. Draw Results Box (if active)
        final hasResults = (_activeTemplate != null || _activeModularTemplate != null);
        final isArea = (_activeTemplate?.id == 'area_circle' || _activeTemplate?.id == 'area_polygon');

        if (hasResults && !isArea) {
             final List<Map<String, String>> items = _getTemplateResultItems();
             final title = _activeModularTemplate?.title ?? _activeTemplate?.title ?? 'Results';

             final fontSize = 14.0 * scaleFactor; 
             final padding = 12.0 * scaleFactor;
             final lineSpacing = 4.0 * scaleFactor;
             
             final textPainter = TextPainter(textDirection: TextDirection.ltr);
             double maxLineWidth = 0;
             double totalTextHeight = 0;
             
             // Measure Title
             textPainter.text = TextSpan(text: title, style: TextStyle(color: Colors.white, fontSize: fontSize * 1.1, fontWeight: FontWeight.bold));
             textPainter.layout();
             maxLineWidth = textPainter.width;
             totalTextHeight += textPainter.height + padding; 
             
             // Measure Items
             for (var item in items) {
                 final span = TextSpan(
                    children: [
                        TextSpan(text: '${item['label']}: ', style: TextStyle(color: Colors.white70, fontSize: fontSize)),
                        TextSpan(text: item['value'], style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
                    ]
                 );
                 textPainter.text = span;
                 textPainter.layout();
                 if (textPainter.width > maxLineWidth) maxLineWidth = textPainter.width;
                 totalTextHeight += textPainter.height + lineSpacing;
             }
             
             final boxWidth = maxLineWidth + (padding * 2);
             final boxHeight = totalTextHeight + (padding * 2);
             
             final screenPos = _infoBoxPosition ?? Offset(20, rootH - 350);
             final dx = screenPos.dx * scaleFactor;
             final dy = screenPos.dy * scaleFactor;
             
             // Box BG
             final bgPaint = Paint()..color = Colors.black.withOpacity(0.8)..style = PaintingStyle.fill;
             final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(dx, dy, boxWidth, boxHeight), Radius.circular(10 * scaleFactor));
             canvas.drawRRect(rrect, bgPaint);
             
             // Box Border
             final borderPaint = Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1.0 * scaleFactor;
             canvas.drawRRect(rrect, borderPaint);
             
             // Paint Title
             double currentY = dy + padding;
             textPainter.text = TextSpan(text: title, style: TextStyle(color: Colors.white, fontSize: fontSize * 1.1, fontWeight: FontWeight.bold));
             textPainter.layout();
             textPainter.paint(canvas, Offset(dx + padding, currentY));
             currentY += textPainter.height + padding/2;
             
             // Paint Items
             for (var item in items) {
                 final span = TextSpan(
                    children: [
                        TextSpan(text: '${item['label']}: ', style: TextStyle(color: Colors.white70, fontSize: fontSize)),
                        TextSpan(text: item['value'], style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
                    ]
                 );
                 textPainter.text = span;
                 textPainter.layout();
                 textPainter.paint(canvas, Offset(dx + padding, currentY));
                 currentY += textPainter.height + lineSpacing;
             }
        }

        // B. Draw Watermark (OrthoQuant MD)
        // Calculate where the image actually is on the captured area
        final Rect imgRect = _calculateImageRect(displaySize!);
        final double imgDx = imgRect.left * scaleFactor;
        final double imgDy = imgRect.top * scaleFactor;
        final double imgW = imgRect.width * scaleFactor;
        final double imgH = imgRect.height * scaleFactor;

        final wmFontSize = 14.0 * scaleFactor;
        final wmPadding = 16.0 * scaleFactor;
        final wmPainter = TextPainter(
          text: TextSpan(
            text: 'OrthoQuant MD',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: wmFontSize,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              shadows: const [
                Shadow(offset: Offset(1, 1), blurRadius: 1, color: Colors.black45),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        wmPainter.layout();
        
        // Position relative to actual IMAGE boundaries
        // Bottom Left of the IMAGE
        wmPainter.paint(canvas, Offset(imgDx + wmPadding, imgDy + imgH - wmPadding - wmPainter.height));

        // 3. Finalize Image
        final finalImage = await recorder.endRecording().toImage(width.toInt(), height.toInt());
        final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData?.buffer.asUint8List();

        if (_imageSize != null) {
             final fullRect = Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height);
             exportPxPerMm = _calculatePxPerMm(fullRect);
        }
      }
    } catch (e) {
      debugPrint('Capture failed: $e');
    }

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExportScreen(
          imagePath: widget.imagePath,
          measurements: _measurements,
          pixelsPerMm: exportPxPerMm, // Pass Image-Space PxPerMm
          capturedImageBytes: pngBytes,
          displaySize: displaySize,
          initialPatientName: _currentRecord.patientName,
          initialPatientId: _currentRecord.patientId,
          initialClinicalNotes: _currentRecord.notes,
          initialGroupId: _currentRecord.groupId,
          customTableData: _buildExportTableData(),
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
       setState(() {
         _currentRecord.patientName = result['patientName'];
         _currentRecord.patientId = result['patientId'];
         _currentRecord.notes = result['notes'];
         _currentRecord.groupId = result['groupId'];
       });
      if (result['action'] == 'saved' || result['action'] == 'shared') {
          _showSuccessAnimation("Export Successful");
      }
       _autoSave();
    }
  }

  List<List<String>> _buildExportTableData() {
     final List<List<String>> rows = [];
     int index = 1;

     // Helper to add row
     void addRow(String label, String value, String unit) {
        rows.add([index.toString(), label, value, unit]);
        index++;
     }

     if (_activeTemplate != null) {
        // TEMPLATE MODE
        
        // 1. Template Outputs (Calculations)
        for (final calc in _activeTemplate!.calculations) {
             final mId = _templateCalculationIds[calc.id];
             if (mId != null) {
                try {
                   final m = _measurements.firstWhere((x) => x.id == mId);
                   // Parse out value based on Calculation ID for specialized formats
                   String text = '';
                   if (calc.id == 'gbl_percent' && m.type == MeasurementType.glenoidDefect) {
                        // Extract % Only
                        String raw = _getMeasurementValueText(m); // "15.2%\nDefect Size: 4.5 mm"
                        if (raw.contains('%')) text = raw.substring(0, raw.indexOf('%'));
                   } else if (calc.id == 'gbl_size' && m.type == MeasurementType.glenoidDefect) {
                        // Extract Size Only
                        String raw = _getMeasurementValueText(m); // "15.2%\nDefect Size: 4.5 mm"
                        if (raw.contains('Defect Size: ')) {
                            // "Defect Size: 4.5 mm"
                            text = raw.split('Defect Size: ').last.trim();
                            // remove unit if handled by column
                            if (text.endsWith('mm')) {
                              text = text.replaceAll('mm', '').trim();
                            } else if (text.endsWith('px')) {
                              text = text.replaceAll('px', '').trim();
                            }
                        }
                   } else {
                       // Standard behavior
                       text = _getMeasurementValueText(m);
                       if (m.label != null && text.startsWith('${m.label}: ')) {
                           text = text.substring(m.label!.length + 2);
                       }
                   }
                   
                   String unit = '';
                   if (calc.id == 'gbl_percent') {
                     unit = '%';
                   }
                   else if (calc.id == 'gbl_size') {
                       // Check if measurement says mm or px
                       String raw = _getMeasurementValueText(m);
                       unit = raw.contains('mm') ? 'mm' : 'px';
                   }
                   else if (text.endsWith('°')) { unit = '°'; text = text.replaceAll('°', ''); }
                   else if (text.startsWith('R: ')) { 
                       // Radius special case
                       text = text.substring(3);
                       if (text.endsWith(' px')) { unit = 'px'; text = text.replaceAll(' px', ''); }
                       if (text.endsWith(' mm')) { unit = 'mm'; text = text.replaceAll(' mm', ''); }
                   }
                   
                   addRow(calc.label, text.trim(), unit);
                } catch (_) {}
             }
        }
        
        // 2. Ad-hoc Measurements (NOT Template Inputs/Outputs)
        final adhoc = _measurements.where((m) {
             if (m.type == MeasurementType.calibration) return false;
             if (m.type == MeasurementType.point) return false; // Exclude simple landmarks/markers
             if (_templateLandmarkMeasurementIds.containsValue(m.id)) return false; // Input
             if (_templateCalculationIds.containsValue(m.id)) return false; // Output (already handled)
             return true;
        });
        
        for (final m in adhoc) {
             _addMeasurementToTable(m, addRow);
        }

     } else {
        // STANDARD MODE (No Template)
        for (final m in _measurements) {
            if (m.type == MeasurementType.calibration) continue;
            if (m.type == MeasurementType.point) continue; // Exclude simple markers
            _addMeasurementToTable(m, addRow);
        }
     }
     
     return rows;
  }

  void _addMeasurementToTable(MeasurementModel m, Function(String, String, String) addRow) {
      String label = m.label ?? (m.type == MeasurementType.cobbAngle ? 'Cobb Angle' : (m.type == MeasurementType.distance ? 'Distance' : 'Angle'));
      String text = _getMeasurementValueText(m);
      
      // Cleanup Label Prefix
      if (m.label != null && text.startsWith('${m.label}: ')) {
          text = text.substring(m.label!.length + 2);
      }
      
      String unit = '';
      if (text.endsWith('°')) { unit = '°'; text = text.replaceAll('°', ''); }
      else if (text.endsWith('mm')) { unit = 'mm'; text = text.replaceAll('mm', ''); }
      else if (text.endsWith('px')) { unit = 'px'; text = text.replaceAll('px', ''); }
       else if (text.endsWith('%')) { unit = '%'; text = text.replaceAll('%', ''); }
      
      // Special Handling for Multi-line (Glenoid) or Complex
      if (text.contains('\n')) {
          // Flatten for table?
          text = text.replaceAll('\n', ' | ');
      }
      
      addRow(label, text.trim(), unit);
  }

  void _syncDependentMeasurements(MeasurementModel source) {
     for (final m in _measurements) {
        if (m.sourceIds != null && m.sourceIds!.contains(source.id)) {
            // Determine logic based on type
            // Assumption: Spinopelvic Pattern (SourceIds: [0]=SS, [1]=HipL, [2]=HipR)
            if ((m.type == MeasurementType.pelvicTilt || m.type == MeasurementType.pelvicIncidence) && m.sourceIds!.length >= 3) {
                 try {
                     final s1 = _measurements.firstWhere((x) => x.id == m.sourceIds![0]);
                     final s2 = _measurements.firstWhere((x) => x.id == m.sourceIds![1]);
                     final s3 = _measurements.firstWhere((x) => x.id == m.sourceIds![2]);
                     
                     if (s1.points.length >= 2 && s2.points.isNotEmpty && s3.points.isNotEmpty) {
                        m.points = [
                           ReferencePoint(s1.points[0].position, label: s1.points[0].label),
                           ReferencePoint(s1.points[1].position, label: s1.points[1].label),
                           ReferencePoint(s2.points[0].position, label: s2.points[0].label),
                           ReferencePoint(s3.points[0].position, label: s3.points[0].label),
                        ];
                     }
                 } catch (_) {}
            }
            // KNEE PATELLA SYNC
            if (m.type == MeasurementType.modifiedInsallSalvati && m.sourceIds!.length >= 2) {
                 // Needs Patella (2 pts) + Tuberosity (1 pt)
                 try {
                     final s1 = _measurements.firstWhere((x) => x.id == m.sourceIds![0]); // Patella
                     final s2 = _measurements.firstWhere((x) => x.id == m.sourceIds![1]); // Tuberosity

                     if (s1.points.length >= 2 && s2.points.isNotEmpty) {
                        m.points = [
                           ReferencePoint(s1.points[0].position, label: s1.points[0].label),
                           ReferencePoint(s1.points[1].position, label: s1.points[1].label),
                           ReferencePoint(s2.points[0].position, label: s2.points[0].label),
                        ];
                     }
                 } catch (_) {}
            }
            if (m.type == MeasurementType.blackburnePeel && m.sourceIds!.length >= 2) {
                 // Needs Patella (2 pts) + Plateau (2 pts)
                 try {
                     final s1 = _measurements.firstWhere((x) => x.id == m.sourceIds![0]); // Patella
                     final s2 = _measurements.firstWhere((x) => x.id == m.sourceIds![1]); // Plateau

                     if (s1.points.length >= 2 && s2.points.length >= 2) {
                        m.points = [
                           ReferencePoint(s1.points[0].position, label: s1.points[0].label),
                           ReferencePoint(s1.points[1].position, label: s1.points[1].label),
                           ReferencePoint(s2.points[0].position, label: s2.points[0].label),
                           ReferencePoint(s2.points[1].position, label: s2.points[1].label),
                        ];
                     }
                 } catch (_) {}
            }
            if (m.type == MeasurementType.glenoidDefect && m.sourceIds!.length >= 2) {
               // Needs Circle (3 pts) + Defect (1 pt)
               try {
                   final s1 = _measurements.firstWhere((x) => x.id == m.sourceIds![0]); // Circle
                   final s2 = _measurements.firstWhere((x) => x.id == m.sourceIds![1]); // Defect

                   if (s1.points.length >= 3 && s2.points.isNotEmpty) {
                      m.points = [
                         ReferencePoint(s1.points[0].position, label: s1.points[0].label),
                         ReferencePoint(s1.points[1].position, label: s1.points[1].label),
                         ReferencePoint(s1.points[2].position, label: s1.points[2].label),
                         ReferencePoint(s2.points[0].position, label: s2.points[0].label),
                      ];
                   }
               } catch (_) {}
          }
        }
     }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePath.isEmpty) return const Scaffold(body: Center(child: Text("No Image")));

    final activeM = _activeMeasurement;
    
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
        title: const Text('OrthoQuant MD', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          Row(
             key: _headerActionsKey,
             mainAxisSize: MainAxisSize.min,
             children: [
                IconButton(
                  // key: _saveBtnKey, // Helper removed
                  icon: const Icon(Icons.save, color: Colors.white),
                  onPressed: _openSaveScreen,
                ),
                IconButton(
                  // key: _exportBtnKey, // Helper removed
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: _exportImage,
                ),
             ],
          ),

        ],
      ),
      body: Stack(
        key: _rootStackKey,
        children: [  
          Column(
            children: [
             
            // CANVAS
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final imageRect = _calculateImageRect(constraints.biggest);
                    
                    // Combine saved and active measurements for unified rendering
                    final allMeasurements = List<MeasurementModel>.from(_measurements);
                    if (_activeMeasurement != null) {
                      allMeasurements.add(_activeMeasurement!);
                    }

                    return Stack(
                      key: _viewportKey, // Assign Key here
                      children: [
                        InteractiveViewer(
                          transformationController: _transformationController,
                          minScale: 1.0,
                          maxScale: 5.0,
                          boundaryMargin: EdgeInsets.symmetric(
                            horizontal: imageRect.width * 0.5,
                            vertical: imageRect.height * 0.5,
                          ),
                          constrained: true,
                          child: GestureDetector(
                            onTapUp: (details) => _handleTapUp(details, imageRect),
                            // onDoubleTapDown: (details) => _handleDoubleTap(details, imageRect), // REMOVED to fix delay
                            child: RepaintBoundary(
                              key: _captureKey,
                              child: ValueListenableBuilder<Matrix4>(
                                valueListenable: _transformationController,
                                builder: (context, matrix, child) {
                                  final scale = matrix.getMaxScaleOnAxis();

                                  return Stack(
                                    fit: StackFit.expand, 
                                    children: [
                                      RepaintBoundary( // Isolate Image Repaint
                                        child: Image.file(
                                          File(widget.imagePath),
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(Icons.broken_image, color: Colors.white, size: 50),
                                                  const SizedBox(height: 8),
                                                  Text('Image not found\n${widget.imagePath.split('/').last}', 
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      
                                      // Paint lines and points (Painter handles denormalization)
                                      CustomPaint(
                                        painter: MeasurementsPainter(
                                          allMeasurements, 
                                          imageRect: imageRect, 
                                          scale: scale, 
                                          strokeWidth: _lineThickness,
                                          textSize: _textSize,
                                          isTextBold: _textBold,
                                          pixelsToMm: _calculatePxPerMm(imageRect),
                                          modularTemplate: _activeModularTemplate,
                                        ),
                                        child: const SizedBox.expand(),
                                      ),

                                      // REMOVED: Inactive Points Loop (Moved to Painter)
                                    
                                    // Draggable Labels - Screen Space & Scaled
                                    ...allMeasurements.asMap().entries.map((entry) {
                                       final m = entry.value;
                                       // Hide TMA Label per user request (InfoBox is enough)
                                       // Also hide Meary's Angle label per user request
                                       if (m.isAuxiliary || m.label == "Meary's Angle" || m.id.endsWith('tma_angle')) return const SizedBox.shrink();
                                       
                                       // Calculate Label Text & Position (DENORMALIZED for Geometry)
                                       String text = '';
                                       Offset defaultPos = Offset.zero;
                                       
                                       // DENORMALIZE Points for calculation
                                       final screenPoints = m.points.map((p) => _denormalizePoint(p.position, imageRect)).toList();

                                       if (m.type == MeasurementType.calibration && screenPoints.length >= 2) {
                                          if (m.calibrationValue != null) {
                                            text = '${m.calibrationValue!.toStringAsFixed(0)} mm';
                                          } else {
                                            text = 'Set Scale';
                                          }
                                          final mid = (screenPoints[0] + screenPoints[1]) / 2;
                                          defaultPos = mid + const Offset(10, -30);
                                       } 
                                       else if (m.type == MeasurementType.glenoidDefect && screenPoints.length >= 4) {
                                            // Calculate Result
                                            // Need Denormalized Points for Geometry? No, Geometry expects Pixels (Offsets).
                                            // _measurements stores NORMALIZED.
                                            // screenPoints ARE Denormalized (Screen Pixels).
                                            final res = GeometryUtils.calculateGlenoidDefect(screenPoints);
                                            if (res != null) {
                                                final radius = res['radius'] as double;
                                                // final lossMms = res['lossMms'] as double;
                                                final percent = res['lossPercent'] as double;
                                                
                                                final imgPxPerMm = _calculatePxPerMm(imageRect);
                                                
                                                if (imgPxPerMm != null) {
                                                   // Convert logic
                                                   // Wait, calculateGlenoidDefect returns PIXEL loss length
                                                   final lossPx = res['lossMms'] as double; 
                                                   final lossMm = lossPx / imgPxPerMm;
                                                   // Need original radius mm?
                                                   // Normal Glenoid usually refers to Diameter or Radius?
                                                   // User said "Normal glenoid (cap?)"
                                                   // I will show Diameter? Or Radius?
                                                   // "Normal glenoid: defekt miktarı: defekt %"
                                                   final rMm = radius / imgPxPerMm;
                                                   final dMm = rMm * 2;
                                                   
                                                   text = 'Normal Glenoid: ${dMm.toStringAsFixed(1)} mm\n'
                                                          'Defect Amount: ${lossMm.toStringAsFixed(1)} mm\n'
                                                          'Defect %: ${percent.toStringAsFixed(1)}%';
                                                } else {
                                                   text = 'Normal Glenoid: ${(radius*2).toStringAsFixed(0)} px\n'
                                                          'Defect Amount: ${(res['lossMms']).toStringAsFixed(0)} px\n'
                                                          'Defect %: ${percent.toStringAsFixed(1)}%';
                                                }
                                                final c = res['center'] as Offset;
                                                defaultPos = c + const Offset(20, 20);
                                            }
                                       } else if (m.type == MeasurementType.angle3Point && screenPoints.length >= 3) {
                                          final p1 = screenPoints[0];
                                          final p2 = screenPoints[1];
                                          final p3 = screenPoints[2];
                                          
                                          final angle = GeometryUtils.calculateAngle(p1, p2, p3);
                                           final valStr = '${angle.toStringAsFixed(1)}°';
                                           text = m.label != null ? '${m.label}\n$valStr' : valStr;
                                          defaultPos = p2 + const Offset(15, -30);
                                       } else if (m.type == MeasurementType.cobbAngle && screenPoints.length >= 4) {
                                          final p1 = screenPoints[0];
                                          final p2 = screenPoints[1];
                                          final p3 = screenPoints[2];
                                          final p4 = screenPoints[3];
                                          
                                          // Calculate Value
                                          final rawLabelPos = m.labelPosition; 
                                          final screenLabelPos = rawLabelPos != null ? _denormalizePoint(rawLabelPos, imageRect) : null;
                                          
                                          // Fallback/Default Pos
                                          defaultPos = (p1 + p2 + p3 + p4) / 4;

                                          final effPos = screenLabelPos ?? defaultPos;
                                          double angle;
                                          
                                          // LAA Logic Fix: If forceAcute, use Static Cobb (ignore labelPos dynamic sector)
                                          if (m.forceAcute) {
                                              angle = GeometryUtils.calculateCobbAngle(p1, p2, p3, p4);
                                          } else {
                                              angle = GeometryUtils.calculateDynamicCobbAngle(p1, p2, p3, p4, effPos);
                                          }
                                          
                                          // Force Acute if requested (Double check)
                                          if (m.forceAcute && angle > 90) {
                                              angle = 180 - angle;
                                          }
                                          
                                          final valStr = '${angle.toStringAsFixed(1)}°';
                                          text = m.label != null ? '${m.label}\n$valStr' : valStr;

                                       } else if (m.type == MeasurementType.distance && screenPoints.length >= 2) {
                                          final distPx = (screenPoints[0] - screenPoints[1]).distance;
                                          double? localPxPerMm;
                                          try {
                                            final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                                            if (calib.points.length >= 2 && calib.calibrationValue != null) {
                                                final cP1 = _denormalizePoint(calib.points[0].position, imageRect);
                                                final cP2 = _denormalizePoint(calib.points[1].position, imageRect);
                                                localPxPerMm = (cP1 - cP2).distance / calib.calibrationValue!;
                                            }
                                          } catch (_) {}

                                          String valStr;
                                          if (localPxPerMm != null) {
                                            valStr = '${(distPx / localPxPerMm).toStringAsFixed(1)} mm';
                                          } else {
                                            valStr = '${distPx.toStringAsFixed(0)} px';
                                          }
                                          text = m.label != null ? '${m.label}\n$valStr' : valStr;
                                          final mid = (screenPoints[0] + screenPoints[1]) / 2;
                                          defaultPos = mid + const Offset(10, -30); 
                                       } else if (m.type == MeasurementType.circle && screenPoints.length >= 2) {
                                          // Circle Radius Logic
                                          final radiusPx = (screenPoints[0] - screenPoints[1]).distance;
                                          double? localPxPerMm;
                                          try {
                                            final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                                            if (calib.points.length >= 2 && calib.calibrationValue != null) {
                                                final cP1 = _denormalizePoint(calib.points[0].position, imageRect);
                                                final cP2 = _denormalizePoint(calib.points[1].position, imageRect);
                                                localPxPerMm = (cP1 - cP2).distance / calib.calibrationValue!;
                                            }
                                          } catch (_) {}
                                          
                                          if (localPxPerMm != null) {
                                             text = 'R: ${(radiusPx / localPxPerMm).toStringAsFixed(1)} mm';
                                          } else {
                                             text = 'R: ${radiusPx.toStringAsFixed(0)} px';
                                          }
                                          // Default Label Position: Midpoint of radius line
                                          final mid = (screenPoints[0] + screenPoints[1]) / 2;
                                          defaultPos = mid + const Offset(0, -20);
                                       } else if (m.type == MeasurementType.circle3Point && screenPoints.length >= 3) {
                                          final res = GeometryUtils.calculateCircleFrom3Points(screenPoints[0], screenPoints[1], screenPoints[2]);
                                          if (res != null) {
                                              final r = res['radius'] as double;
                                              final c = res['center'] as Offset;
                                              double? localPxPerMm = _calculatePxPerMm(imageRect);
                                              
                                              if (localPxPerMm != null) {
                                                  text = 'R: ${(r / localPxPerMm).toStringAsFixed(1)} mm';
                                              } else {
                                                  text = 'R: ${r.toStringAsFixed(1)} px';
                                              }
                                              defaultPos = c;
                                          }
                                       } else if (m.type == MeasurementType.sacralSlope && screenPoints.length >= 2) {
                                           final val = GeometryUtils.calculateSacralSlope(m.points[0].position, m.points[1].position);
                                           text = 'SS: ${val.toStringAsFixed(1)}°';
                                           final mid = (screenPoints[0] + screenPoints[1]) / 2;
                                           defaultPos = mid + const Offset(10, -30);
                                       } else if (m.type == MeasurementType.pelvicTilt && screenPoints.length >= 4) {
                                           final val = GeometryUtils.calculatePelvicTilt(m.points[0].position, m.points[1].position, m.points[2].position, m.points[3].position);
                                           text = 'PT: ${val.toStringAsFixed(1)}°';
                                           final hipCenter = (screenPoints[2] + screenPoints[3]) / 2;
                                           defaultPos = hipCenter + const Offset(10, -50);
                                       } else if (m.type == MeasurementType.pelvicIncidence && screenPoints.length >= 4) {
                                           final val = GeometryUtils.calculatePelvicIncidence(m.points[0].position, m.points[1].position, m.points[2].position, m.points[3].position);
                                           text = 'PI: ${val.toStringAsFixed(1)}°';
                                           text = 'PI: ${val.toStringAsFixed(1)}°';
                                           final s1Center = (screenPoints[0] + screenPoints[1]) / 2;
                                           defaultPos = s1Center + const Offset(10, 30);
                                        } else if (m.type == MeasurementType.areaCircle && screenPoints.length >= 2) {
                                           text = _getMeasurementValueText(m);
                                           final mid = (screenPoints[0] + screenPoints[1]) / 2;
                                           defaultPos = mid;
                                        } else if (m.type == MeasurementType.areaPolygon && screenPoints.length >= 3) {
                                           text = _getMeasurementValueText(m);
                                           // Centroid
                                           double sx = 0, sy = 0;
                                           for (final p in screenPoints) {
                                              sx += p.dx; sy += p.dy;
                                           }
                                           defaultPos = Offset(sx / screenPoints.length, sy / screenPoints.length);
                                        } else if (m.type == MeasurementType.modifiedInsallSalvati && screenPoints.length >= 3) {
                                           final val = GeometryUtils.calculateModifiedInsallSalvati(m.points[0].position, m.points[1].position, m.points[2].position);
                                           text = 'mIS: ${val.toStringAsFixed(1)}';
                                           defaultPos = screenPoints[1] + const Offset(20, 0); // Near pInf
                                       } else if (m.type == MeasurementType.blackburnePeel && screenPoints.length >= 4) {
                                           final val = GeometryUtils.calculateBlackburnePeel(m.points[0].position, m.points[1].position, m.points[2].position, m.points[3].position);
                                           text = 'BP: ${val.toStringAsFixed(1)}';
                                           defaultPos = screenPoints[1] + const Offset(20, 20); // Near pInf
                                       }

                                       if (text.isEmpty) return const SizedBox.shrink();

                                       final normPos = m.labelPosition; 
                                       
                                       Offset renderPos;
                                       if (normPos != null) {
                                          renderPos = _denormalizePoint(normPos, imageRect);
                                       } else {
                                          renderPos = defaultPos;
                                       }
                                       // Hide floating labels if a template is active (User Request: Results go to Results Box)
                                        // EXCLUDE Area Templates (Circle/Polygon) -> They stay on canvas
                                        if (_activeTemplate != null && !['area_circle', 'area_polygon'].contains(_activeTemplate!.id)) {
                                            return const SizedBox.shrink();
                                        }
                                        
                                        // Old individual logic removed for general rule above
                                        if (m.type == MeasurementType.glenoidDefect) return const SizedBox.shrink();

                                       return Positioned(
                                         left: renderPos.dx,
                                         top: renderPos.dy,
                                         child: GestureDetector(
                                           behavior: HitTestBehavior.opaque,
                                           onPanStart: (d) => _updateMagnifierFromLocalPoint(renderPos),
                                           onPanEnd: (_) => _hideMagnifier(),
                                           onPanCancel: () => _hideMagnifier(),
                                           onPanUpdate: (details) {
                                             setState(() {
                                                final localDelta = details.delta;
                                                final currentScreenPos = renderPos;
                                                final newScreenPos = currentScreenPos + localDelta;
                                                m.labelPosition = _normalizePoint(newScreenPos, imageRect);
                                                  
                                                _updateMagnifierFromLocalPoint(newScreenPos);
                                             });
                                           },
                                           onTap: (m.type == MeasurementType.calibration && !m.isLocked) ? _showCalibrationDialog : null, 

                                            child: MeasurementLabelBox(
                                              text: text,
                                              color: m.color,
                                              scale: scale,
                                              isBold: _textBold,
                                              fontSize: _textSize,
                                            ),

                                        ),
                                      );
                                    }),

                                    // Draggable Points (Active or Selected) - Scaled
                                    ...[..._measurements, if (_activeMeasurement != null) _activeMeasurement!]
                                        .where((m) => (m == _activeMeasurement || m.id == _selectedMeasurementId) && !m.isLocked && !m.isTemplateResult)
                                        .expand((m) {
                                          return m.points.asMap().entries.map((entry) {
                                             final index = entry.key;
                                             final p = entry.value;
                                             final screenPos = _denormalizePoint(p.position, imageRect);
                                             
                                             final touchSize = 48.0 / scale;
                                             final visualSize = ((SettingsService().landmarkSize + 2.0) * 5.0) / scale;
                                             final borderWidth = 2.0 / scale;

                                             return Positioned(
                                               left: screenPos.dx - (touchSize / 2),
                                               top: screenPos.dy - (touchSize / 2),
                                               child: GestureDetector(
                                                 behavior: HitTestBehavior.opaque,
                                                 onTapDown: (_) {
                                                     // Start Timer for Smart Zoom (1.5 seconds)
                                                     _smartZoomTimer?.cancel();
                                                     _smartZoomTimer = Timer(const Duration(milliseconds: 1200), () {
                                                         if (mounted && _autoZoomEnabled) {
                                                             setState(() {
                                                                // Activate Smart Zoom
                                                                _preSmartZoomMatrix = _transformationController.value.clone();
                                                                final currentScale = _transformationController.value.getMaxScaleOnAxis();
                                                                // Target 2.2x Zoom
                                                                if (currentScale < 2.2) {
                                                                   _animateZoom(2.2, screenPos);
                                                                }
                                                             });
                                                         }
                                                     });
                                                 },
                                                 onTapUp: (_) {
                                                     _smartZoomTimer?.cancel();
                                                     // Cleanup if zoom was active
                                                     if (_preSmartZoomMatrix != null) {
                                                         _animateMatrix(_preSmartZoomMatrix!);
                                                         _preSmartZoomMatrix = null;
                                                     }
                                                 },
                                                 onTapCancel: () {
                                                     _smartZoomTimer?.cancel();
                                                 },
                                                 onPanStart: (d) {
                                                    _updateMagnifierFromLocalPoint(screenPos);
                                                    if (_smartZoomTimer != null && _smartZoomTimer!.isActive) {
                                                       _smartZoomTimer!.cancel();
                                                    }
                                                 },
                                                 onPanEnd: (_) {
                                                     _hideMagnifier();
                                                     _smartZoomTimer?.cancel();
                                                     if (_autoZoomEnabled && _preSmartZoomMatrix != null) {
                                                         _animateMatrix(_preSmartZoomMatrix!);
                                                         _preSmartZoomMatrix = null;
                                                     }
                                                      if (_activeTemplate != null || _activeModularTemplate != null) {
                                                          setState(() {
                                                             _generateTemplateOutputs();
                                                          });
                                                      }
                                                 },
                                                 onPanCancel: () {
                                                     _hideMagnifier();
                                                     _smartZoomTimer?.cancel();
                                                     if (_autoZoomEnabled && _preSmartZoomMatrix != null) {
                                                         _animateMatrix(_preSmartZoomMatrix!);
                                                         _preSmartZoomMatrix = null;
                                                     }
                                                 },
                                                 onPanUpdate: (d) {
                                                   setState(() {
                                                      final localDelta = d.delta;
                                                      final newScreenPos = screenPos + localDelta;
                                                      final newNorm = _normalizePoint(newScreenPos, imageRect);
                                                       m.points[index] = ReferencePoint(newNorm, label: p.label);
                                                       
                                                       _syncDependentMeasurements(m);
                                                       if (_activeTemplate != null || _activeModularTemplate != null) {
                                                          _generateTemplateOutputs();
                                                       }
                                                       _updateMagnifierFromLocalPoint(newScreenPos);
                                                   });
                                                 },
                                                 child: Container(
                                                   width: touchSize, height: touchSize,
                                                   alignment: Alignment.center,
                                                   child: Container(
                                                     width: visualSize, height: visualSize,
                                                     decoration: (_activeTemplate != null && _templateLandmarkMeasurementIds.containsValue(m.id)) ? 
                                                        BoxDecoration(
                                                           color: Colors.black, // Landmark Style
                                                           shape: BoxShape.circle,
                                                           border: Border.all(color: Colors.white, width: 2.0/scale)
                                                        ) : 
                                                        BoxDecoration(
                                                           color: m.color.withValues(alpha: 0.5),
                                                           shape: BoxShape.circle,
                                                           border: Border.all(color: Colors.white, width: borderWidth)
                                                        ),
                                                   ),
                                                 ),
                                               ),
                                             );
                                          });
                                       }),
                                       
                                    // Calibration Warning (Inner Stack) - Scaled
                                    // Calibration Warning (Inner Stack) - Scaled


                                    ],
                                  ); // End Inner Stack
                                },
                              ), // End ValueListenableBuilder
                            ), // End RepaintBoundary
                          ), // End GestureDetector
                        ), // End InteractiveViewer
                        
                        // GUIDE BANNER (New Logic)
                        if (_activeTemplate != null && _activeMeasurement != null)
                           Builder(
                             builder: (context) {
                                // We are in a template.
                                // Find current landmark
                                if (_activeLandmarkIndex >= _activeTemplate!.landmarks.length) {
                                    // Done
                                    return const SizedBox.shrink();
                                }
                                
                                final lm = _activeTemplate!.landmarks[_activeLandmarkIndex];
                                final totalGlobalSteps = _activeTemplate!.landmarks.length;
                                final currentGlobalStep = _activeLandmarkIndex + 1;
                                
                                return Positioned(
                                  top: 80, // Below menu
                                  left: 20,
                                  right: 20,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(30),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))
                                      ]
                                    ),
                                    child: Row(
                                      children: [
                                        // Step Indicator
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.yellowAccent,
                                            borderRadius: BorderRadius.circular(12)
                                          ),
                                          child: Text(
                                            '$currentGlobalStep / $totalGlobalSteps',
                                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Instruction Text
                                        Expanded(
                                          child: Text(
                                            lm.instruction,
                                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                            // overflow: TextOverflow.ellipsis, // Removed to allow wrap
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ); 
                           }),


                        // OVERLAY SUBMENU (Fixed on Screen - Outer Stack)
                        if (activeM != null)
                          Positioned(
                            top: 10, // Moved to TOP
                            left: 20,
                            right: 20,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 50,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900]?.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))
                                    ]
                                  ),
                                   child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Step Indicator (Hide if complete)
                                        if (activeM.type != MeasurementType.calibration && activeM.points.length < activeM.totalSteps) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: activeM.color.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: activeM.color.withValues(alpha: 0.5))
                                            ),
                                            child: Text(
                                              'Step ${activeM.activeStep}/${activeM.totalSteps}',
                                              style: TextStyle(color: activeM.color, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 8), 
                                          const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10, width: 20),
                                        ],
       
                                        if (!_hasCalibration)
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                            tooltip: 'Calibration Needed',
                                            onSelected: (_) => _createNewMeasurement(MeasurementType.calibration),
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'calibrate',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.straighten, color: Colors.black54),
                                                    SizedBox(width: 8),
                                                    Text('Calibrate Now'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        // Color
                                        IconButton(
                                          icon: const Icon(Icons.color_lens, color: Colors.white),
                                          onPressed: () {
                                              setState(() {
                                                int currentIndex = _availableColors.indexOf(activeM.color);
                                                int nextIndex = (currentIndex + 1) % _availableColors.length;
                                                activeM.color = _availableColors[nextIndex];
                                              });
                                          },
                                          tooltip: 'Change Color',
                                        ),
                                        // Duplicate (Hide for Calibration)
                                        if (activeM.type != MeasurementType.calibration)
                                          IconButton(
                                            icon: const Icon(Icons.copy, color: Colors.white),
                                            onPressed: _duplicateMeasurement,
                                            tooltip: 'Duplicate',
                                          ),
                                        // Delete
                                         IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                                          onPressed: _deleteMeasurement,
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                
                                // WARNING REMOVED PER USER REQUEST
                              ],
                            ),
                          ),
                          
                        // TEMPLATE INFO BOX (Top Right)
                        // TEMPLATE INFO BOX (Top Right)
                        // EXCLUDE Area Templates (Circle/Polygon) -> They use labels
                        if (_activeTemplate != null && !['area_circle', 'area_polygon'].contains(_activeTemplate!.id) && _getTemplateResultItems().isNotEmpty)
                           Positioned(
                              left: _infoBoxPosition?.dx ?? 20,
                              top: _infoBoxPosition?.dy ?? (MediaQuery.of(context).size.height - 350), // Default Higher to avoid overlap
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                   setState(() {
                                      final currentPos = _infoBoxPosition ?? Offset(20, MediaQuery.of(context).size.height - 350);
                                      _infoBoxPosition = currentPos + details.delta;
                                   });
                                },
                                child: TemplateRegistry.all.firstWhere((t) => t.id == _activeTemplate!.id).buildResultBox(
                                   context,
                                   _modularResults,
                                   () => setState(() => _modularResults.clear()),
                                ),
                              ),
                           ),


                          
                        // MEASUREMENT LIST (Chips)
                        if (_measurements.isNotEmpty)
                          Positioned(
                            bottom: 10, 
                            left: 0,
                            right: 0,
                            child: _buildMeasurementList(),
                          ),

                        // INFO BUTTON (Educational Content)
                        if (_activeTemplate != null && _activeTemplate!.infoDescription != null)
                          Positioned(
                            top: 160, 
                            left: 20,
                            child: GestureDetector(
                              onTap: _openInfoDialog,
                              child: const Icon(Icons.info_outline, color: Colors.white, size: 32),
                            ),
                          ),
                          
                        // MAGNIFIER (Top Layer)
                         if (_magnifierPosition != null)
                           Positioned(
                             left: _magnifierPosition!.dx - 62.5, // Center (125/2)
                             top: _magnifierPosition!.dy - 145, // Shift UP (125 size + 20 gap)
                             child: RawMagnifier(
                               decoration: const MagnifierDecoration(
                                 shape: CircleBorder(
                                   side: BorderSide(color: Colors.white, width: 2),
                                 ),
                                 shadows: [
                                   BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2)
                                 ]
                               ),
                               size: const Size(125, 125), // 100 * 1.25 = 125
                               magnificationScale: 1.5, // 2.0 * 0.75 = 1.5
                               focalPointOffset: const Offset(0, 82.5), // CenterY (dy-145+62.5 = dy-82.5) -> Target dy -> Offset +82.5
                               child: Stack(
                                 children: [
                                   // Brightness/Contrast Enhancer
                                   Positioned.fill(
                                     child: CustomPaint(
                                       painter: _MagnifierOverlayPainter(),
                                     ),
                                   ),
                                   Center(
                                     child: Container(
                                       width: 6,
                                       height: 6,
                                       decoration: const BoxDecoration(
                                         color: Colors.red,
                                         shape: BoxShape.circle
                                       ),
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                           ),
                          
                          // FLOATING FINISH BUTTON (For Polygon)
                          if (_activeMeasurement != null && 
                              _activeMeasurement!.type == MeasurementType.areaPolygon && 
                              _activeMeasurement!.points.length >= 3 && 
                              !_activeMeasurement!.isLocked)
                            Positioned(
                              right: 20,
                              bottom: 130, // Above bottom menu
                              child: FloatingActionButton(
                                onPressed: _finishPolygon,
                                backgroundColor: Colors.greenAccent,
                                child: const Icon(Icons.check_circle, color: Colors.black, size: 32),
                              ),
                            ),
                          
                          // PERMANENT CALIBRATION BUTTON
                          Positioned(
                              right: _calibBtnOffset.dx,
                              bottom: _calibBtnOffset.dy,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    // Origin is Bottom-Right.
                                    // Drag Right (+dx) -> Decrease Right Offset (closer to edge) -> offset -= dx
                                    // Drag Up (-dy) -> Increase Bottom Offset (further from bottom) -> offset -= dy
                                    // wait, Drag Right (+dx) -> Decrease Right offset?
                                    // If right=100, drag right (+10) -> right=90. Correct.
                                    // Drag Left (-10) -> right=110. Correct.
                                    // Drag Down (+10) -> Decrease Bottom offset -> bottom -= dy. Correct.
                                    // Drag Up (-10) -> Increase Bottom offset -> bottom -= dy. Correct.
                                    _calibBtnOffset -= details.delta;
                                  });
                                },
                                child: FloatingActionButton.small(
                                  key: _calibBtnKey,
                                  heroTag: 'calib_btn',
                                  backgroundColor: _measurements.any((m) => m.type == MeasurementType.calibration && m.calibrationValue != null) ? Colors.blue.withValues(alpha: 0.8) : Colors.orangeAccent,
                                  onPressed: _showCalibrationDialog,
                                  child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                                ),
                              ),
                          ),
                      ],
                    );
                  }
                ),
              ),
           ),



            // BOTTOM MENU
            Container(
               key: _menuKey, // Target for tutorial
               height: 112, // Increased from 100 to fix overflow
               color: Colors.black,
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceAround,
                 children: [

                    _buildBottomButton(
                      icon: Icons.architecture, 
                      label: 'Angle',
                      isActive: _activeMeasurement?.type == MeasurementType.angle3Point,
                      onTap: () => _createNewMeasurement(MeasurementType.angle3Point)
                    ),
                    
                    _buildBottomButton(
                      customIcon: CobbIcon(color: _activeMeasurement?.type == MeasurementType.cobbAngle ? const Color(0xFF00BFA5) : Colors.white70),
                      label: 'Cobb',
                      isActive: _activeMeasurement?.type == MeasurementType.cobbAngle,
                      onTap: () => _createNewMeasurement(MeasurementType.cobbAngle)
                    ),


                    _buildBottomButton(
                      icon: Icons.straighten,
                      label: 'Distance',
                      isActive: _activeMeasurement?.type == MeasurementType.distance,
                      onTap: () => _createNewMeasurement(MeasurementType.distance)
                    ),

                    // CIRCLE BUTTON 
                     Expanded(
                      child: PopupMenuButton<MeasurementType>(
                        offset: const Offset(0, -120),
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white24)),
                        onSelected: (type) {
                          if (type == MeasurementType.circle3Point && !SubscriptionService().isPro) {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
                          } else {
                             _createNewMeasurement(type);
                          }
                        },
                        itemBuilder: (context) => [
                           _buildMenuItem(MeasurementType.circle, 'Center-Radius', Icons.radio_button_unchecked),
                           _buildMenuItem(MeasurementType.circle3Point, '3-Point Circle', Icons.change_history, isPremium: true),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                               mainAxisSize: MainAxisSize.min,
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                  Icon(Icons.radio_button_unchecked, color: (_activeMeasurement?.type == MeasurementType.circle || _activeMeasurement?.type == MeasurementType.circle3Point) ? const Color(0xFF00BFA5) : Colors.white70, size: 28),
                                  const SizedBox(height: 4),
                                  Text('Circle', style: TextStyle(color: (_activeMeasurement?.type == MeasurementType.circle || _activeMeasurement?.type == MeasurementType.circle3Point) ? const Color(0xFF00BFA5) : Colors.white70, fontSize: 12)),
                               ],
                            ),
                        ),
                      ),
                    ),

                    // Area Menu
                    Expanded(
                      child: PopupMenuButton<MeasurementType>(
                        offset: const Offset(0, -120),
                        color: Colors.grey[900],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white24)),
                        onSelected: (type) {
                          if (!SubscriptionService().isPro) {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
                          } else {
                             _createNewMeasurement(type);
                          }
                        },
                        itemBuilder: (context) => [
                          _buildMenuItem(MeasurementType.areaCircle, 'Circle Area', Icons.radio_button_unchecked, isPremium: true),
                          _buildMenuItem(MeasurementType.areaPolygon, 'Polygon Area', Icons.polyline, isPremium: true),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.texture, color: (_activeMeasurement?.type == MeasurementType.areaCircle || _activeMeasurement?.type == MeasurementType.areaPolygon) ? const Color(0xFF00BFA5) : Colors.white70, size: 28),
                              const SizedBox(height: 4),
                              Text('Area', style: TextStyle(color: (_activeMeasurement?.type == MeasurementType.areaCircle || _activeMeasurement?.type == MeasurementType.areaPolygon) ? const Color(0xFF00BFA5) : Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    _buildBottomButton(
                      icon: _isMenuOpen ? Icons.close : Icons.assignment,
                      label: 'Templates',
                      isActive: _activeTemplate != null || _isMenuOpen,
                      onTap: () => _toggleMenu(),
                    ),
                 ],
               ),
            ),
          ],
        ),
         _buildTemplateMenuOverlay(),
        ],
      ),
    );
  }

  // Helper to extract value text
  String _getMeasurementValueText(MeasurementModel m) {
      if (_imageSize == null) return '';
      final fullImageRect = Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height);
      final imgPoints = m.points.map((p) => _denormalizePoint(p.position, fullImageRect)).toList();
      
      String valueText = '';
      if (m.type == MeasurementType.angle3Point && imgPoints.length >= 3) {
           final val = GeometryUtils.calculateAngle(imgPoints[0], imgPoints[1], imgPoints[2]);
           valueText = '${val.toStringAsFixed(1)}°';
       } else if (m.type == MeasurementType.cobbAngle && imgPoints.length >= 4) {
           final labelPos = m.labelPosition != null ? _denormalizePoint(m.labelPosition!, fullImageRect) : null;
           double angle;
           if (labelPos == null || m.forceAcute) {
               angle = GeometryUtils.calculateCobbAngle(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
           } else {
               angle = GeometryUtils.calculateDynamicCobbAngle(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3], labelPos);
           }
           if (m.forceAcute && angle > 90) {
               angle = 180 - angle;
           }
           valueText = '${angle.toStringAsFixed(1)}°';
       } else if (m.type == MeasurementType.distance && imgPoints.length >= 2) {
           final dist = (imgPoints[0] - imgPoints[1]).distance;
           double? imgPxPerMm;
           try {
               final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
               if (calib.points.length >= 2 && calib.calibrationValue != null) {
                  final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                  final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                  imgPxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
               }
           } catch (_) {}

           if (imgPxPerMm != null) {
             valueText = '${(dist / imgPxPerMm).toStringAsFixed(1)} mm';
           } else {
             valueText = '${dist.toStringAsFixed(0)} px';
           }
       } else if ((m.type == MeasurementType.circle || m.type == MeasurementType.circle3Point) && m.points.length >= 2) { // 3-point circle handled via radius
           double radiusPx = 0;
           if (m.type == MeasurementType.circle) {
               radiusPx = (imgPoints[0] - imgPoints[1]).distance;
           } else if (m.type == MeasurementType.circle3Point && imgPoints.length >= 3) {
                final res = GeometryUtils.calculateCircleFrom3Points(imgPoints[0], imgPoints[1], imgPoints[2]);
                if (res != null) radiusPx = res['radius'];
           }
           
            double? imgPxPerMm;
           try {
               final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
               if (calib.points.length >= 2 && calib.calibrationValue != null) {
                  final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                  final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                  imgPxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
               }
           } catch (_) {}

           if (imgPxPerMm != null) {
             valueText = 'R: ${(radiusPx / imgPxPerMm).toStringAsFixed(1)} mm';
           } else {
             valueText = 'R: ${radiusPx.toStringAsFixed(0)} px';
           }

         } else if (m.type == MeasurementType.spinopelvic) {
             if (imgPoints.length >= 6) {
                 try {
                     final params = GeometryUtils.calculateSpinopelvic(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[4]);
                     valueText = 'Sacral Slope: ${params['SS']!.toStringAsFixed(1)}°\nPelvic Tilt: ${params['PT']!.toStringAsFixed(1)}°\nPelvic Incidence: ${params['PI']!.toStringAsFixed(1)}°';
                 } catch (e) {
                     valueText = 'Error';
                 }
             } else {
                 valueText = 'Waiting for points... (${imgPoints.length}/6)';
             }
         } else if (m.type == MeasurementType.sacralSlope && imgPoints.length >= 2) {
             final val = GeometryUtils.calculateSacralSlope(imgPoints[0], imgPoints[1]);
             valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.pelvicTilt && imgPoints.length >= 4) {
              final val = GeometryUtils.calculatePelvicTilt(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
              valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.pelvicIncidence && imgPoints.length >= 4) {
              final val = GeometryUtils.calculatePelvicIncidence(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
              valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.glenoidVersion && imgPoints.length >= 3) {
             final res = GeometryUtils.calculateGlenoidVersion(imgPoints); // Correctly passes list
             
             double retroversion = res['retroversion']!;
             double medializationPx = res['medialization']!;
             double subluxation = res['subluxation'] ?? 0.0;
             
             String medText = '${medializationPx.toStringAsFixed(0)} px';

             // Check calibration for medialization
             try {
                final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                if (calib.points.length >= 2 && calib.calibrationValue != null) {
                    final fullImageRect = Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height);
                    final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                    final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                    final pxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
                    medText = '${(medializationPx / pxPerMm).toStringAsFixed(1)} mm';
                }
             } catch (_) {}

             String text = 'Retroversion: ${retroversion.toStringAsFixed(1)}°\nMedialization: $medText';
             
             // Add Subluxation if available (points D/E set)
             if (imgPoints.length >= 5) {
                text += '\nPost. Subluxation: ${subluxation.toStringAsFixed(0)}%';
             }
             
             valueText = text;
         } else if (m.type == MeasurementType.acromialIndex && imgPoints.length >= 4) {
             final val = GeometryUtils.calculateAcromialIndex(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
             valueText = val.toStringAsFixed(1);
         } else if (m.type == MeasurementType.blackburnePeel && imgPoints.length >= 4) {
             try {
                // Not standard logic here, usually result box. But for list...
                final res = GeometryUtils.calculateBlackburnePeel(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
                valueText = res.toStringAsFixed(1);
             } catch (_) { valueText = '...'; }
         } else if (m.type == MeasurementType.modifiedInsallSalvati && imgPoints.length >= 3) {
             try {
                final res = GeometryUtils.calculateModifiedInsallSalvati(imgPoints[0], imgPoints[1], imgPoints[2]);
                valueText = res.toStringAsFixed(1);
             } catch (_) { valueText = '...'; } 
         } else if (m.type == MeasurementType.talonavicularCoverage && imgPoints.length >= 4) {
             final val = GeometryUtils.calculateTNCA(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
             valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.talonavicularUncoverage && imgPoints.length >= 3) {
             final val = GeometryUtils.calculateTNUP(imgPoints[0], imgPoints[1], imgPoints[2]);
             valueText = '${val.toStringAsFixed(1)}%';
         } else if (m.type == MeasurementType.talarIncongruency && imgPoints.length >= 3) {
             final val = GeometryUtils.calculateTalarIncongruency(imgPoints[0], imgPoints[1], imgPoints[2]);
             valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.calcanealPitch && imgPoints.length >= 2) {
             final val = GeometryUtils.calculateCalcanealPitch(imgPoints[0], imgPoints[1]);
             valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.talocalcanealAngle && imgPoints.length >= 4) {
             final val = GeometryUtils.calculateTalocalcanealAngle(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
             valueText = '${val.toStringAsFixed(1)}°';
          } else if (m.type == MeasurementType.lcea && imgPoints.length >= 6) {
              final val = GeometryUtils.calculateLCEA(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3], imgPoints[4], imgPoints[5]);
              valueText = '${val.toStringAsFixed(1)}°';
          } else if (m.type == MeasurementType.tonnisAngle && imgPoints.length >= 4) {
              final val = GeometryUtils.calculateTonnisAngle(imgPoints[0], imgPoints[1], imgPoints[2], imgPoints[3]);
              valueText = '${val.toStringAsFixed(1)}°';
         } else if (m.type == MeasurementType.glenoidDefect && imgPoints.length >= 4) {
             final res = GeometryUtils.calculateGlenoidDefect(imgPoints);
             if (res != null) {
                  final lossPercent = res['lossPercent'] as double;
                  // lossLength in pixels (misnamed 'lossMms' in geometry utils return)
                  final lossPx = res['lossMms'] as double; 
                  
                  String linearVal = '';
                  double? imgPxPerMm;
                   try {
                       final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                       if (calib.points.length >= 2 && calib.calibrationValue != null) {
                          final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                          final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                          imgPxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
                       }
                   } catch (_) {}

                  if (imgPxPerMm != null) {
                      linearVal = '${(lossPx / imgPxPerMm).toStringAsFixed(1)} mm';
                  } else {
                      linearVal = '${lossPx.toStringAsFixed(0)} px';
                  }

                   valueText = 'Bone Loss: ${lossPercent.toStringAsFixed(1)}%\nDefect Size: $linearVal';
              } else {
                   valueText = 'Error';
              }
          } else if (m.type == MeasurementType.areaCircle && imgPoints.length >= 2) {
              // Center-edge method: radius = distance from center to edge
              final center = imgPoints[0];
              final edge = imgPoints[1];
              final radiusPx = (center - edge).distance;
              final areaPx = math.pi * radiusPx * radiusPx;
              
              double? imgPxPerMm;
              try {
                  final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                  if (calib.points.length >= 2 && calib.calibrationValue != null) {
                     final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                     final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                     imgPxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
                  }
              } catch (_) {}

              if (imgPxPerMm != null) {
                final areaMm2 = areaPx / (imgPxPerMm * imgPxPerMm);
                if (areaMm2 > 999) {
                  valueText = '${(areaMm2 / 100).toStringAsFixed(1)} cm²';
                } else {
                  valueText = '${areaMm2.toStringAsFixed(1)} mm²';
                }
              } else {
                valueText = '${areaPx.toStringAsFixed(1)} px²';
              }
          } else if (m.type == MeasurementType.areaPolygon && imgPoints.length >= 3) {
              final areaPx = GeometryUtils.calculatePolygonArea(imgPoints);
              
              double? imgPxPerMm;
              try {
                  final calib = _measurements.firstWhere((c) => c.type == MeasurementType.calibration);
                  if (calib.points.length >= 2 && calib.calibrationValue != null) {
                     final cp1 = _denormalizePoint(calib.points[0].position, fullImageRect);
                     final cp2 = _denormalizePoint(calib.points[1].position, fullImageRect);
                     imgPxPerMm = (cp1 - cp2).distance / calib.calibrationValue!;
                  }
              } catch (_) {}

              if (imgPxPerMm != null) {
                final areaMm2 = areaPx / (imgPxPerMm * imgPxPerMm);
                if (areaMm2 > 999) {
                  valueText = '${(areaMm2 / 100).toStringAsFixed(1)} cm²';
                } else {
                  valueText = '${areaMm2.toStringAsFixed(1)} mm²';
                }
              } else {
                valueText = '${areaPx.toStringAsFixed(1)} px²';
              }
          } else if (m.type == MeasurementType.point) {
             // No value for a single point, just show label
          }
         
         if (valueText.isNotEmpty && m.label != null && m.label!.isNotEmpty) {
             if (!valueText.startsWith(m.label!)) {
                 return '${m.label}: $valueText';
             }
         }
         return valueText.isEmpty ? (m.label ?? 'Measurement') : valueText;
  }

  List<Map<String, String>> _getTemplateResultItems() {
      // MODULAR RESULTS (Parsed)
      if (_activeModularTemplate != null) {
          return _modularResults.map((r) {
              final parts = r.split(': ');
              if (parts.length >= 2) {
                  return {'label': parts[0], 'value': parts.sublist(1).join(': ')};
              }
              return {'label': 'Result', 'value': r};
          }).toList();
      }

      if (_activeTemplate == null) return [];
      
      final List<Map<String, String>> list = [];
      for (final calc in _activeTemplate!.calculations) {
          if (calc.isAuxiliary) continue; // Hide auxiliary lines from results per user request
          
          final mId = _templateCalculationIds[calc.id];
          if (mId == null) {
              list.add({'label': calc.label, 'value': '...'});
              continue;
          }
          
          try {
              final m = _measurements.firstWhere((x) => x.id == mId);
              String raw = _getMeasurementValueText(m);
              
              // SPECIAL HANDLING: Glenoid Version (Multi-line split)
              if (m.type == MeasurementType.glenoidVersion && raw.contains('\n')) {
                  final lines = raw.split('\n');
                  // Item 1: Retroversion
                  String val1 = lines[0];
                  if (val1.startsWith('Retroversion: ')) val1 = val1.replaceAll('Retroversion: ', '');
                  list.add({'label': calc.label, 'value': val1});
                  
                  // Item 2+: Parse distinct lines
                  for (int i = 1; i < lines.length; i++) {
                      final parts = lines[i].split(': ');
                      if (parts.length >= 2) {
                          list.add({'label': parts[0].trim(), 'value': parts.sublist(1).join(': ').trim()});
                      } else {
                          list.add({'label': '', 'value': lines[i]});
                      }
                  }
                  continue;
              }

              // SPECIAL HANDLING: Glenoid Defect (Split into 2 outputs defined in template)
              String value = '';
              if (m.type == MeasurementType.glenoidDefect) {
                  if (calc.id == 'gbl_percent') {
                      value = raw.contains('\n') ? raw.split('\n').first : raw;
                  } else if (calc.id == 'gbl_size') {
                      value = raw.contains('Defect Size: ') ? raw.split('Defect Size: ').last.trim() : '';
                  } else {
                      value = raw;
                  }
              } else {
                  // STANDARD BEHAVIOR
                  value = raw;
                  // Strip Redundant Label
                  if (m.label != null && value.startsWith('${m.label}: ')) {
                      value = value.substring(m.label!.length + 2);
                  } else if (value.contains(': ')) {
                      final parts = value.split(': ');
                      if (parts.length > 1 && (parts[0] == m.label || parts[0] == calc.label)) {
                          value = parts.sublist(1).join(': ');
                      }
                  }
              }
              
              list.add({'label': calc.label, 'value': value});
          } catch (_) {
              list.add({'label': calc.label, 'value': '...'});
          }
      }
      return list;
  }

  Widget _buildMeasurementList() {
     // Filter out auxiliary measurements (e.g. Glenoid Result)
     final displayList = _measurements.where((m) => !m.isAuxiliary).toList();
     if (displayList.isEmpty) return const SizedBox.shrink();

     return Stack(
      children: [
        SingleChildScrollView(
          controller: _listScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8), 
          child: Row(
            children: displayList.map((m) { 
               return GestureDetector(
                   onTap: () {
                     if (!m.isAuxiliary) {
                        setState(() {
                           _selectedMeasurementId = m.id;
                        });
                     }
                   },
                   child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedMeasurementId == m.id ? m.color.withValues(alpha: 0.2) : Colors.black54,
                        border: Border.all(color: _selectedMeasurementId == m.id ? m.color : Colors.white24),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Container(width: 8, height: 8, decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
                           const SizedBox(width: 8),
                           Text(
                             _getMeasurementValueText(m),
                             style: const TextStyle(color: Colors.white, fontSize: 12),
                           ),
                           if (_selectedMeasurementId == m.id) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _deleteMeasurement,
                                child: const Icon(Icons.close, size: 16, color: Colors.white70),
                              )
                           ]
                        ],
                      ),
                   ),
                );
            }).toList(),
          ),
        ),
        
        // Left Arrow
        if (_showLeftArrow)
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: GestureDetector(
               onTap: () => _listScrollController.animateTo(_listScrollController.offset - 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
               child: Container(width: 24, color: Colors.black.withValues(alpha: 0.3), alignment: Alignment.center, child: const Icon(Icons.arrow_left, color: Colors.white, size: 24)),
            ),
          ),
          
        // Right Arrow
        if (_showRightArrow)
          Positioned(
            right: 0, top: 0, bottom: 0,
            child: GestureDetector(
               onTap: () => _listScrollController.animateTo(_listScrollController.offset + 100, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
               child: Container(width: 24, color: Colors.black.withValues(alpha: 0.3), alignment: Alignment.center, child: const Icon(Icons.arrow_right, color: Colors.white, size: 24)),
            ),
          ),
      ]
     );
  }


   PopupMenuItem<MeasurementType> _buildMenuItem(MeasurementType type, String label, IconData icon, {bool isPremium = false}) {
     return PopupMenuItem<MeasurementType>(
       value: type,
       child: Row(
         children: [
           Icon(icon, color: Colors.white70),
           const SizedBox(width: 12),
           Text(label, style: const TextStyle(color: Colors.white)),
           if (isPremium && !SubscriptionService().isPro) ...[
             const SizedBox(width: 8),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
               decoration: BoxDecoration(
                 color: Colors.amber,
                 borderRadius: BorderRadius.circular(8),
               ),
               child: const Text('PRO', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
             ),
           ],
         ],
       ),
     );
   }

  Widget _buildBottomButton({IconData? icon, Widget? customIcon, required String label, bool isActive = false, required VoidCallback onTap, Key? key}) {
      return Expanded( // Ensure it takes available space for easier tap
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque, // Catch taps even on whitespace
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8), // Reduced from 16
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 AnimatedContainer(
                   duration: const Duration(milliseconds: 200),
                   curve: Curves.easeOut,
                   padding: const EdgeInsets.all(6), // Reduced from 8
                   decoration: isActive ? BoxDecoration(
                     color: Colors.white24,
                     borderRadius: BorderRadius.circular(8)
                   ) : BoxDecoration(
                     color: Colors.transparent,
                     borderRadius: BorderRadius.circular(8)
                   ),
                   child: customIcon ?? Icon(icon, color: isActive ? const Color(0xFF00BFA5) : Colors.white70, size: 24) // Reduced from 28
                 ),
                 const SizedBox(height: 2), // Reduced from 4
                 Text(label, style: TextStyle(color: isActive ? const Color(0xFF00BFA5) : Colors.white70, fontSize: 10))  // Reduced from 12
              ],
            ),
          ),
        ),
      );
  }
}

class CobbIcon extends StatelessWidget {
  final Color color;
  const CobbIcon({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: CobbPainter(color),
    );
  }
}

class CobbPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  CobbPainter(this.color, {this.strokeWidth = 2.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Vertebrae (Rounded Rects)
    // Top
    _drawRotatedRect(canvas, paint, cx + 2, cy - 8, -15 * 3.14159 / 180);
    // Mid
    _drawRotatedRect(canvas, paint, cx - 2, cy, 0);
    // Bot
    _drawRotatedRect(canvas, paint, cx + 2, cy + 8, 15 * 3.14159 / 180);

    // Lines (Abstract intersection)
    // Top Line (extending from top vert)
    canvas.drawLine(Offset(cx - 8, cy - 10), Offset(cx + 8, cy - 14), paint..strokeWidth = 1.5);
    // Bot Line (extending from bot vert)
    canvas.drawLine(Offset(cx - 8, cy + 10), Offset(cx + 8, cy + 14), paint);
  }

  void _drawRotatedRect(Canvas canvas, Paint paint, double x, double y, double angle) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 10, height: 6), const Radius.circular(2)), paint..strokeWidth = 1.5);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MeasurementsPainter extends CustomPainter {
  final List<MeasurementModel> measurements;
  final Rect imageRect;
  final double scale;
  final double strokeWidth;
  final double textSize;
  final bool isTextBold;
  final double? pixelsToMm;

  MeasurementsPainter(
    this.measurements, {
    required this.imageRect, 
    required this.scale, 
    this.strokeWidth = 2.0,
    required this.textSize,
    required this.isTextBold,
    this.pixelsToMm,
    this.modularTemplate, // Receive it
  });

  final MeasurementTemplateBase? modularTemplate;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;
    
    // NEW: Modular Template Painting
    if (modularTemplate != null) {
       // Aggregate all points (assuming they are landmarks)
       // This is a simplification; ideally we track which measurement belongs to the template.
       // But for the FAI template pilot, all single points are landmarks.
       List<ReferencePoint> allPoints = [];
       for (final m in measurements) {
           if (m.type == MeasurementType.point) {
               allPoints.addAll(m.points);
           }
       }
       
       // Delegate to Template
       if (allPoints.isNotEmpty) {
           modularTemplate!.paint(canvas, allPoints, scale, Paint()..color = const Color(0xFF00FF00)..strokeWidth=strokeWidth, imageRect);
       }
       // Ghosting Fix: We want to skip "Result Measurements" which are duplicate representations.
       // But we MUST draw "Calibration" or other manual measurements if they exist.
    }

    for (final m in measurements) {
      // 2. Skip "Ghost" Results
    // Heuristic: If Template Active, don't draw template-generated results UNLESS it is Calibration.
    if (modularTemplate != null && m.isTemplateResult && m.type != MeasurementType.calibration) continue;

      _paintMeasurement(canvas, m);

      // 3. Draw Points (REPLACES widget-based loop for performance)
      _paintMeasurementPoints(canvas, m);
    }
  }

  void _paintMeasurementPoints(Canvas canvas, MeasurementModel m) {
    if (m.points.isEmpty || m.isTemplateResult) return; // Hide results points per user request

    final isLandmark = (modularTemplate != null && m.type == MeasurementType.point);
    final baseSize = SettingsService().landmarkSize * 5.0;
    final radius = (baseSize / 2) / scale;

    // Paints
    final landmarkPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    
    final landmarkBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 / scale;

    final standardPaint = Paint()
      ..color = m.type == MeasurementType.calibration ? Colors.white : m.color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final standardBorderPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale;

    for (final p in m.points) {
      final screenPos = Offset(
        imageRect.left + p.position.dx * imageRect.width,
        imageRect.top + p.position.dy * imageRect.height,
      );

      if (isLandmark) {
        canvas.drawCircle(screenPos, radius, landmarkPaint);
        canvas.drawCircle(screenPos, radius, landmarkBorderPaint);
      } else {
        canvas.drawCircle(screenPos, radius, standardPaint);
        canvas.drawCircle(screenPos, radius, standardBorderPaint);
      }
    }
  }
  
  void _drawCustomLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {bool isDashed = false, bool isInfinite = false}) {
    // 1. Draw the core segment (between p1 and p2)
    if (isDashed) {
      _drawDashedLine(canvas, p1, p2, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
    }

    // 2. Draw extensions if infinite
    if (isInfinite) {
      final infPoints = GeometryUtils.getInfiniteLinePoints(p1, p2, imageRect);
      if (infPoints != null && infPoints.length >= 2) {
        final v = p2 - p1;
        if (v.distance > 0) {
          for (final b in infPoints) {
            // Check if boundary point b is "behind" p1
            final vP1B = b - p1;
            final dotP1 = vP1B.dx * v.dx + vP1B.dy * v.dy;
            if (dotP1 < -0.01) {
              _drawDashedLine(canvas, p1, b, paint);
              continue;
            }

            // Check if boundary point b is "ahead" of p2
            final vP2B = b - p2;
            final dotP2 = vP2B.dx * v.dx + vP2B.dy * v.dy;
            if (dotP2 > 0.01) {
              _drawDashedLine(canvas, p2, b, paint);
            }
          }
        }
      }
    }
  }
  
  
  void _paintMeasurement(Canvas canvas, MeasurementModel m) {
    if (m.points.isEmpty) return;

    final paint = Paint()
      ..color = m.color
      ..strokeWidth = (m.type == MeasurementType.calibration ? 2.0 : strokeWidth) / scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    Offset denormalize(Offset p) {
       if (imageRect.isEmpty) return p;
       return Offset(
         imageRect.left + p.dx * imageRect.width, 
         imageRect.top + p.dy * imageRect.height
       );
    }
    
    final points = m.points.map((rp) => denormalize(rp.position)).toList();
    final labelPos = m.labelPosition != null ? denormalize(m.labelPosition!) : null;

    final pointRadius = SettingsService().landmarkSize / scale;
    final crossSize = (SettingsService().landmarkSize + 1.0) / scale;

    if (points.length >= 2) {
       if (m.type == MeasurementType.calibration) {
          _drawDashedLine(canvas, points[0], points[1], paint);
       } else if (m.type == MeasurementType.angle3Point && points.length >= 3) {
          _drawCustomLine(canvas, points[0], points[1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          _drawCustomLine(canvas, points[1], points[2], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          _drawAngleArc(canvas, paint, points[0], points[1], points[2]);
          
       } else if (m.type == MeasurementType.cobbAngle && points.length >= 4) {
          final p1 = points[0];
          final p2 = points[1];
          final p3 = points[2];
          final p4 = points[3];
          
          // Dynamic Cobb Painter Logic
          // Top Line
          canvas.drawLine(p1, p2, paint);
          // Bot Line
          canvas.drawLine(p3, p4, paint);
          
          // Extension Lines (Dotted)
          // Calculate Intersect
          final i = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
          if (i != null) {
             final dottedPaint = Paint()
               ..color = m.color.withValues(alpha: 0.7)
               ..style = PaintingStyle.stroke
               ..strokeWidth = (strokeWidth * 0.5) / scale // Thinner extension
               ..strokeCap = StrokeCap.round;
               
             _drawDashedLine(canvas, (p1+p2)/2, i, dottedPaint);
             _drawDashedLine(canvas, (p3+p4)/2, i, dottedPaint);
          }
          
          // Highlight Endplates?
          paint.strokeWidth = (strokeWidth + 2.0) / scale; // Slightly thicker caps
          canvas.drawPoints(ui.PointMode.points, [p1,p2,p3,p4], paint);
          paint.strokeWidth = strokeWidth / scale; // Reset

          _drawCobbArc(canvas, paint, points[0], points[1], points[2], points[3], labelPos, m.forceAcute);
       } else if (m.type == MeasurementType.cobbAngle && points.length >= 2) {
          _drawCustomLine(canvas, points[0], points[1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
       } else if (m.type == MeasurementType.circle || m.type == MeasurementType.areaCircle) {
          // CIRCLE DRAWING
          final center = points[0];
          final edge = points[1];
          final radius = (center - edge).distance;
          
          // Circle
          canvas.drawCircle(center, radius, paint);
          
          // Fill for Area (Faint)
          if (m.type == MeasurementType.areaCircle) {
             canvas.drawCircle(center, radius, paint..style=PaintingStyle.fill..color=m.color.withValues(alpha: 0.15));
             // Restore stroke for other parts if needed (but we are done with paint object here mostly)
             paint..style = PaintingStyle.stroke ..color = m.color; 
          }
          
          // Radius Line
          canvas.drawLine(center, edge, paint..strokeWidth = 1.5 / scale);
          
          // Center Cross
          canvas.drawLine(center - Offset(crossSize, 0), center + Offset(crossSize, 0), paint);
          canvas.drawLine(center - Offset(0, crossSize), center + Offset(0, crossSize), paint);
       } else if (m.type == MeasurementType.areaPolygon && points.length >= 2) {
          // POLYGON DRAWING
          final path = Path()..moveTo(points[0].dx, points[0].dy);
          for (int k = 1; k < points.length; k++) {
              path.lineTo(points[k].dx, points[k].dy);
          }
          if (m.isLocked) {
              path.close();
              // Fill
              canvas.drawPath(path, paint..style=PaintingStyle.fill..color=m.color.withValues(alpha: 0.15));
              paint..style = PaintingStyle.stroke ..color = m.color;
          }
          canvas.drawPath(path, paint);
          
          // Draw vertices
          for (final p in points) {
              canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
          }

       } else if (m.type == MeasurementType.sacralSlope && points.length >= 2) {
          // SACRAL SLOPE (2 pts - S1)
          canvas.drawLine(points[0], points[1], paint);
          
          // Horizontal Ref
          final s1Center = (points[0] + points[1]) / 2;
          final hLen = 40.0 / scale;
          final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(s1Center - Offset(hLen, 0), s1Center + Offset(hLen, 0), auxPaint);
          
          // DRAW TEXT REMOVED (Handled by Widget)
          
       } else if (m.type == MeasurementType.pelvicTilt && points.length >= 4) {
          // PELVIC TILT (S1: P1-P2, Hips: P3, P4)
          // Note: Reuse copies points, so we draw them too?
          // Maybe just the Pelvic Radius and Vertical.
          
          final s1Center = (points[0] + points[1]) / 2;
          final hipCenter = (points[2] + points[3]) / 2;
          
          // Draw Pelvic Radius with Thinner line
          final radiusPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(hipCenter, s1Center, radiusPaint);
          
          // Vertical Ref at Hip Center (Thinner, Dashed)
          final vLen = 60.0 / scale;
          final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          _drawDashedLine(canvas, hipCenter - Offset(0, vLen), hipCenter + Offset(0, vLen/2), auxPaint);

          // DRAW TEXT REMOVED (Handled by Widget)

       } else if (m.type == MeasurementType.pelvicIncidence && points.length >= 4) {
          // PELVIC INCIDENCE (S1: P1-P2, Hips: P3, P4)
          final s1Center = (points[0] + points[1]) / 2;
          final hipCenter = (points[2] + points[3]) / 2;
          
          // Draw Pelvic Radius (Faint/Thin)
          final radiusPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(hipCenter, s1Center, radiusPaint);
          
          // Perpendicular to S1 (Thin)
          final vs1 = points[1] - points[0];
          // Rotated 90
          final perp = Offset(-vs1.dy, vs1.dx);
          final normPerp = perp / perp.distance;
          final pLen = 50.0 / scale;
          
          final perpPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
          canvas.drawLine(s1Center, s1Center + normPerp * pLen, perpPaint);

          // DRAW TEXT REMOVED (Handled by Widget)

       } else if (m.type == MeasurementType.spinopelvic && points.length >= 6) {
          // SPINOPELVIC DRAWING
          final p1 = points[0]; // S1 P1
          final p2 = points[1]; // S1 P2
          final c1 = points[2]; // Hip 1 Center
          final r1 = (points[3] - c1).distance;
          final c2 = points[4]; // Hip 2 Center
          final r2 = (points[5] - c2).distance;
          
          // Draw S1 Line
          canvas.drawLine(p1, p2, paint);
          
          // Draw Hip Circles
          canvas.drawCircle(c1, r1, paint);
          canvas.drawCircle(c2, r2, paint);
          // Crosses for centers
          canvas.drawLine(c1 - Offset(crossSize, 0), c1 + Offset(crossSize, 0), paint);
          canvas.drawLine(c2 - Offset(crossSize, 0), c2 + Offset(crossSize, 0), paint);
          canvas.drawLine(c2 - Offset(0, crossSize), c2 + Offset(0, crossSize), paint);
          
          // Calculate Geometry
           GeometryUtils.calculateSpinopelvic(p1, p2, c1, c2);
          final s1Center = (p1 + p2) / 2;
          final hipCenter = (c1 + c2) / 2;
          
          // Draw Hip Axis (Dashed)
          final auxPaint = Paint()
             ..color = paint.color.withValues(alpha: 0.7)
             ..strokeWidth = 1.5 / scale
             ..style = PaintingStyle.stroke;

          _drawDashedLine(canvas, c1, c2, auxPaint);
          
          // Draw Pelvic Radius (Hip Center -> S1 Center)
          canvas.drawLine(hipCenter, s1Center, paint..strokeWidth=2.0/scale);
          
          // Draw References
          // Horizontal through S1 Center (for SS)
          final hLen = 40.0 / scale;
          canvas.drawLine(s1Center - Offset(hLen, 0), s1Center + Offset(hLen, 0), auxPaint);
          
          // Vertical through Hip Center (for PT)
          final vLen = 60.0 / scale;
          canvas.drawLine(hipCenter - Offset(0, vLen), hipCenter + Offset(0, vLen/2), auxPaint); // Up mostly
          
       } else if (m.type == MeasurementType.lcea && points.length >= 6) {
          // points: 0,1=Teardrops, 2,3,4=FH, 5=Source
          // 1. Pelvic Axis Video
          final pAxisVec = points[1] - points[0];
          // 2. FH Center
          final fhCenter = GeometryUtils.getCircleCenter(points[2], points[3], points[4]);
          // 3. Vertical (Perp to Axis)
          final verticalVec = Offset(-pAxisVec.dy, pAxisVec.dx); // rotate 90
          // Draw Vertical from Center
          // Make sure vertical goes UP (compare Y). Screen Y is down.
          // If pAxisVec is roughly (1, 0), vertical is (0, 1) [Down]. We want (0, -1).
          Offset safeVert = verticalVec;
          if (safeVert.dy > 0) safeVert = -safeVert; // Force UP
          
          final vLineEnd = fhCenter + (safeVert / safeVert.distance) * (100.0/scale);
          _drawDashedLine(canvas, fhCenter, vLineEnd, paint..strokeWidth = 1.0/scale);

          // 4. Center-Edge Line
          canvas.drawLine(fhCenter, points[5], paint..strokeWidth = 2.0/scale);
          
          // Draw FH Circle (Auxiliary visual)
          if (fhCenter != Offset.zero) {
              final r = (points[2] - fhCenter).distance;
              canvas.drawCircle(fhCenter, r, paint..strokeWidth=1.0/scale..color=paint.color.withValues(alpha:0.5));
          }

       } else if (m.type == MeasurementType.tonnisAngle && points.length >= 4) {
          // 0,1=Teardrops, 2=Med, 3=Lat
          // Draw Pelvic Axis (Light)
          canvas.drawLine(points[0], points[1], paint..strokeWidth = 1.0/scale..color=paint.color.withValues(alpha:0.5));
          // Draw Sourcil Line
          canvas.drawLine(points[2], points[3], paint..strokeWidth = 2.0/scale);
          
          // Visualizing angle intersection
          final intersection = GeometryUtils.getLineIntersection(points[0], points[1], points[2], points[3]);
          if (intersection != null) {
              _drawDashedLine(canvas, points[3], intersection, paint..strokeWidth=1.0/scale);
          }
       
       } else if (m.type == MeasurementType.modifiedInsallSalvati) {
          // mIS: Sup(0)->Inf(1), Tub(2)
          if (points.length >= 2) {
             // Articular Line
             canvas.drawLine(points[0], points[1], paint);
          }
          if (points.length >= 3) {
             // Tendon Line (Thin/Distinct)
             final tendonPaint = Paint()..color = paint.color..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
             canvas.drawLine(points[1], points[2], tendonPaint);
          }

       } else if (m.type == MeasurementType.blackburnePeel) {
          // BP: Sup(0)->Inf(1), PlatPost(2)->PlatAnt(3)
          if (points.length >= 2) {
             // Articular Line
             canvas.drawLine(points[0], points[1], paint);
          }
          if (points.length >= 4) {
              // Plateau Line (2-3)
              canvas.drawLine(points[2], points[3], paint);
              
              // Perpendicular (Inf(1) -> Project onto 2-3)
              final pInf = points[1];
              final pPost = points[2];
              final pAnt = points[3];
              
              final vPlat = pAnt - pPost;
              if (vPlat.distance > 0) {
                  final vInf = pInf - pPost;
                  final t = (vInf.dx * vPlat.dx + vInf.dy * vPlat.dy) / (vPlat.dx*vPlat.dx + vPlat.dy*vPlat.dy);
                  final projected = pPost + vPlat * t;
                  
                  // Thin Dashed Line
                  final dashPaint = Paint()..color = paint.color..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
                  _drawDashedLine(canvas, pInf, projected, dashPaint);
              }
          }

       } else if (m.type == MeasurementType.circle3Point) {
          // Draw points
          for (final p in points) {
               canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
          }
          if (points.length >= 3) {
              final res = GeometryUtils.calculateCircleFrom3Points(points[0], points[1], points[2]);
              if (res != null) {
                  final c = res['center'] as Offset;
                  final r = res['radius'] as double;
                  canvas.drawCircle(c, r, paint..style=PaintingStyle.stroke);
                  
                  // Center cross
                  canvas.drawLine(c - Offset(crossSize, 0), c + Offset(crossSize, 0), paint);
                  canvas.drawLine(c - Offset(0, crossSize), c + Offset(0, crossSize), paint);
              }
          }
       } else if (m.type == MeasurementType.acromialIndex && points.length >= 4) {
          final p1 = points[0]; 
          final p2 = points[1]; 
          final pA = points[2]; 
          final pH = points[3]; 
          
          canvas.drawLine(p1, p2, paint);
          
          final vLine = p2 - p1;
          if (vLine.distance > 0) {
              final dashPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;

              final vA = pA - p1;
              final tA = (vA.dx * vLine.dx + vA.dy * vLine.dy) / (vLine.dx * vLine.dx + vLine.dy * vLine.dy);
              final projA = p1 + vLine * tA;
              _drawDashedLine(canvas, pA, projA, dashPaint);
              
              final vH = pH - p1;
              final tH = (vH.dx * vLine.dx + vH.dy * vLine.dy) / (vLine.dx * vLine.dx + vLine.dy * vLine.dy);
              final projH = p1 + vLine * tH;
              _drawDashedLine(canvas, pH, projH, dashPaint);
          }
       } else if (m.type == MeasurementType.glenoidDefect) {
           if (points.length >= 4) {
               final res = GeometryUtils.calculateGlenoidDefect(points);
               if (res != null) {
                   final c = res['center'] as Offset;
                   final r = res['radius'] as double;
                   final defect = res['defectPoint'] as Offset;
                   
                   // Draw Best Fit Circle (Dashed or Thin)
                   final thinPaint = Paint()..color = m.color ..strokeWidth = 1.0/scale ..style = PaintingStyle.stroke;
                   canvas.drawCircle(c, r, thinPaint);
                   
                   // Draw Defect Point (Circle)
                   canvas.drawCircle(defect, pointRadius, Paint()..color=Colors.red..style=PaintingStyle.fill);
                   
                   // Draw Line from Center to Defect
                   final linePaint = Paint()..color = Colors.redAccent ..strokeWidth = 2.0/scale ..style = PaintingStyle.stroke;
                   canvas.drawLine(c, defect, linePaint);
                   
                   // Draw Center
                   canvas.drawCircle(c, pointRadius * 0.75, Paint()..color=Colors.white);
               }
           }
       } else if (m.type == MeasurementType.talonavicularCoverage && points.length >= 4) {
           final p1 = points[0];
           final p2 = points[1];
           final p3 = points[2];
           final p4 = points[3];
           
           canvas.drawLine(p1, p2, paint);
           canvas.drawLine(p3, p4, paint);
           
           // Extension lines
           final i = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
           if (i != null) {
               final dottedPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 1.0/scale;
               _drawDashedLine(canvas, (p1+p2)/2, i, dottedPaint);
               _drawDashedLine(canvas, (p3+p4)/2, i, dottedPaint);
           }
           // Arc
           _drawCobbArc(canvas, paint, p1, p2, p3, p4, labelPos, m.forceAcute);
           
       } else if (m.type == MeasurementType.talonavicularUncoverage && points.length >= 3) {
           final pLat = points[0];
           final pMed = points[1]; 
           final pNav = points[2];
           
           canvas.drawLine(pLat, pMed, paint);
           
           final c = (pLat + pMed) / 2;
           canvas.drawCircle(pNav, pointRadius, paint..style=PaintingStyle.fill);
           canvas.drawCircle(c, pointRadius * 0.75, Paint()..color=Colors.white);

           // Draw dashed line C-P
           final dashPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
           _drawDashedLine(canvas, c, pNav, dashPaint);
       
       } else if (m.type == MeasurementType.calcanealPitch && points.length >= 2) {
           canvas.drawLine(points[0], points[1], paint);
           final p1 = points[0]; final p2 = points[1];
           final lowPt = (p1.dy > p2.dy) ? p1 : p2;
           final hLen = 60.0 / scale;
           final auxPaint = Paint()..color = paint.color.withValues(alpha: 0.7)..strokeWidth = 1.0/scale..style=PaintingStyle.stroke;
           canvas.drawLine(lowPt - Offset(hLen, 0), lowPt + Offset(hLen, 0), auxPaint);

       } else if (m.type == MeasurementType.talocalcanealAngle && points.length >= 4) {
           final p1 = points[0]; final p2 = points[1];
           final p3 = points[2]; final p4 = points[3];
           canvas.drawLine(p1, p2, paint);
           canvas.drawLine(p3, p4, paint);
           _drawCobbArc(canvas, paint, p1, p2, p3, p4, labelPos, m.forceAcute);

       } else if (m.type == MeasurementType.areaCircle) {
           if (points.length >= 2) {
               final center = points[0];
               final edge = points[1];
               final radius = (center - edge).distance;
               canvas.drawCircle(center, radius, paint..style=PaintingStyle.stroke);
               final fillPaint = Paint()..color = m.color.withValues(alpha: 0.2)..style = PaintingStyle.fill;
               canvas.drawCircle(center, radius, fillPaint);
               canvas.drawLine(center, edge, paint..strokeWidth = 1.5 / scale);
                canvas.drawLine(center - Offset(crossSize, 0), center + Offset(crossSize, 0), paint..style=PaintingStyle.stroke);
                canvas.drawLine(center - Offset(0, crossSize), center + Offset(0, crossSize), paint);
           }
       } else if (m.type == MeasurementType.areaPolygon) {
           for (final p in points) {
                canvas.drawCircle(p, pointRadius, paint..style=PaintingStyle.fill);
           }
           if (points.length >= 2) {
               for (int i = 0; i < points.length - 1; i++) {
                   canvas.drawLine(points[i], points[i + 1], paint..style=PaintingStyle.stroke);
               }
               if (m.isLocked && points.length >= 3) {
                   canvas.drawLine(points.last, points.first, paint);
                   final fillPaint = Paint()..color = m.color.withValues(alpha: 0.2)..style = PaintingStyle.fill;
                   final path = Path();
                   path.moveTo(points.first.dx, points.first.dy);
                   for (int i = 1; i < points.length; i++) {
                       path.lineTo(points[i].dx, points[i].dy);
                   }
                   path.close();
                   canvas.drawPath(path, fillPaint);
               }
           }
       } else if (m.type == MeasurementType.talarIncongruency && points.length >= 3) {
           canvas.drawLine(points[0], points[1], paint);
           canvas.drawLine(points[1], points[2], paint);
           _drawAngleArc(canvas, paint, points[0], points[1], points[2]);
           
       } else if (m.type == MeasurementType.glenoidVersion && points.length >= 3) {
           final A = points[0];
           final B = points[1];
           final C = points[2];
           for (int i=0; i<3; i++) {
                canvas.drawCircle(points[i], pointRadius, paint..style=PaintingStyle.fill);
           }
           if (points.length >= 5) {
               canvas.drawCircle(points[3], pointRadius, paint..style=PaintingStyle.fill);
               canvas.drawCircle(points[4], pointRadius, paint..style=PaintingStyle.fill);
           }
           canvas.drawLine(B, C, paint);
           final M = (B + C) / 2;
           final axisPaint = Paint()..color = paint.color..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
           _drawDashedLine(canvas, A, M, axisPaint);
           final vAM = M - A;
           if (vAM.distance > 0) {
               final vPerp = Offset(-vAM.dy, vAM.dx) / vAM.distance;
               final visLen = 60.0 / scale;
               final mStart = M - vPerp * visLen;
               final mEnd = M + vPerp * visLen;
               _drawDashedLine(canvas, mStart, mEnd, axisPaint); 
               final cStart = C - vPerp * visLen;
               final cEnd = C + vPerp * visLen;
               _drawDashedLine(canvas, cStart, cEnd, axisPaint);
               if (points.length >= 5) {
                   final D = points[3];
                   final E = points[4];
                   final subPaint = Paint()..color = paint.color.withValues(alpha: 0.8)..strokeWidth = 1.5/scale..style=PaintingStyle.stroke;
                   canvas.drawLine(D, E, subPaint);
                   final intersection = GeometryUtils.getLineIntersection(A, M, D, E);
                   if (intersection != null) {
                       _drawDashedLine(canvas, M, intersection, axisPaint);
                       canvas.drawCircle(intersection, 3.0/scale, Paint()..color=Colors.white);
                   }
               }
           }
       } else {
          // Distance / Polyline / Standard Line fallback
          for (int i=0; i < points.length - 1; i++) {
            _drawCustomLine(canvas, points[i], points[i+1], paint, isDashed: m.isDashed, isInfinite: m.isInfinite);
          }
       }
    }
  }



  void _drawCobbArc(Canvas canvas, Paint basePaint, Offset p1, Offset p2, Offset p3, Offset p4, Offset? labelPos, bool forceAcute) {
      final intersection = GeometryUtils.getLineIntersection(p1, p2, p3, p4);
      if (intersection == null) return;
      
      const double piVal = 3.14159265;

      double t1 = (p2 - p1).direction % piVal; 
      if (t1 < 0) t1 += piVal; 
      double t2 = (p4 - p3).direction % piVal;
      if (t2 < 0) t2 += piVal;
      
      final angles = [t1, t2, t1 + piVal, t2 + piVal]..sort();
      
      double targetAngle;
      
      if (labelPos != null && !forceAcute) {
         final vLabel = labelPos - intersection;
         if (vLabel.distance == 0) return;
         targetAngle = vLabel.direction;
      } else {
         // Default to Bisector of Acute Angle
         // Or just pick the acute sector
         // Vectors u and v
         var u = (p2 - p1);
         var v = (p4 - p3);
         
         // Ensure dot product is positive for acute angle between vectors
         if ((u.dx * v.dx + u.dy * v.dy) < 0) {
            v = -v;
         }
         final bisect = u + v;
         targetAngle = bisect.direction;
      }

      if (targetAngle < 0) targetAngle += 2 * piVal; 
      
      double start = 0;
      double sweep = 0;
      
      bool inInterval(double a, double s, double e) {
          if (s <= e) return a >= s && a <= e;
          return a >= s || a <= e; 
      }
      
      for (int i = 0; i < 4; i++) {
          final s = angles[i];
          final e = angles[(i + 1) % 4];
          
          if (inInterval(targetAngle, s, e)) {
             start = s;
             sweep = e - s;
             if (sweep < 0) sweep += 2 * piVal;
             break;
          }
      }
      
      final arcPaint = Paint()
        ..color = basePaint.color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
        
      final radius = (SettingsService().landmarkSize * 5.0) / scale;
      canvas.drawArc(
        Rect.fromCircle(center: intersection, radius: radius),
        start,
        sweep,
        false,
        arcPaint
      );
  }

  void _drawAngleArc(Canvas canvas, Paint basePaint, Offset p1, Offset p2, Offset p3) {
      const double piVal = 3.14159265;
      
      final v1 = p1 - p2;
      final v2 = p3 - p2;
      
      if (v1.distance == 0 || v2.distance == 0) return;
      
      double a1 = v1.direction;
      double a2 = v2.direction;
      
      double diff = a2 - a1;
      while (diff <= -piVal) {
        diff += 2*piVal;
      }
      while (diff > piVal) {
        diff -= 2*piVal;
      }
      
      final arcPaint = Paint()
        ..color = basePaint.color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
        
      final radius = (SettingsService().landmarkSize * 5.0) / scale;
      canvas.drawArc(
        Rect.fromCircle(center: p2, radius: radius),
        a1,
        diff,
        false,
        arcPaint
      );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    var max = (p2 - p1).distance;
    var dashWidth = 10.0 / scale;
    var dashSpace = 5.0 / scale;
    var startY = 0.0;
    final normalized = (p2 - p1) / max;
    
    while (startY < max) {
      final lineStart = p1 + normalized * startY;
      final lineEnd = p1 + normalized * (startY + dashWidth > max ? max : startY + dashWidth);
      canvas.drawLine(lineStart, lineEnd, paint);
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant MeasurementsPainter oldDelegate) {
    return oldDelegate.scale != scale || 
           oldDelegate.imageRect != imageRect || 
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.measurements != measurements ||
           oldDelegate.textSize != textSize ||
           oldDelegate.isTextBold != isTextBold ||
           oldDelegate.pixelsToMm != pixelsToMm;
  }
}

class SuccessOverlay extends StatefulWidget {
  final String message;
  const SuccessOverlay({super.key, required this.message});
  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]
                ),
                child: const Icon(Icons.check, color: Color(0xFF00BFA5), size: 48),
              ),
            ),
            const SizedBox(height: 16),
            DefaultTextStyle(
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              child: Text(widget.message),
            )
          ],
        ),
      ),
    );
  }
}


class _MagnifierOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Brighten the magnified image using BlendMode.screen
    // This adds light to the image, making dark areas more visible.
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25) // Adjust opacity for brightness level
      ..blendMode = BlendMode.screen;
      
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
