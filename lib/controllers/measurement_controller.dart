import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/services/history_service.dart';

/// Owns the measurement data layer for [MeasurementScreen]:
///   - The list of [MeasurementModel]s
///   - The current selection
///   - The current drawing tool
///   - The persistence record (autosave + image relocation)
///
/// This is the first stage of the controller-based architecture migration.
/// The screen still performs some inline mutations on [measurements] for
/// historical reasons (e.g. tap-to-add-point logic). Those mutations rely
/// on [setState] for redraw and bypass [notifyListeners]; that is intentional
/// for the 2.1 step and will be tightened in subsequent phases.
class MeasurementController extends ChangeNotifier {
  MeasurementController({
    required String imagePath,
    MeasurementRecord? initialRecord,
  }) {
    if (initialRecord != null) {
      _record = initialRecord;
      _measurements.addAll(initialRecord.measurements);
    } else {
      _record = MeasurementRecord(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        imagePath: imagePath,
        // Same list reference so the record always sees current state.
        measurements: _measurements,
      );
    }
  }

  final HistoryService _historyService = HistoryService();
  final Uuid _uuid = const Uuid();

  final List<MeasurementModel> _measurements = [];
  String? _selectedId;
  MeasurementType _currentTool = MeasurementType.angle3Point;
  late MeasurementRecord _record;

  static const List<Color> _availableColors = [
    Color(0xFF00BFA5), // Teal
    Color(0xFFFF4081), // Pink
    Color(0xFF2979FF), // Blue
    Color(0xFFB388FF), // Purple
    Color(0xFF76FF03), // Light Green
    Color(0xFFFF6E40), // Deep Orange
    Color(0xFF18FFFF), // Cyan Accent
  ];

  /// Read-only access to the colour palette used by [getNextColor] and the
  /// per-measurement colour cycler in the UI.
  List<Color> get palette => _availableColors;

  // ============================================================
  // Getters
  // ============================================================

  /// Live, mutable list. Direct mutations bypass [notifyListeners] — call
  /// the controller's API methods (or wrap in `setState` at the call site)
  /// when you need a redraw.
  List<MeasurementModel> get measurements => _measurements;

  String? get selectedId => _selectedId;
  MeasurementType get currentTool => _currentTool;
  MeasurementRecord get record => _record;

  bool get hasCalibration =>
      _measurements.any((m) => m.type == MeasurementType.calibration);

  MeasurementModel? get activeMeasurement {
    if (_selectedId == null) return null;
    try {
      return _measurements.firstWhere((m) => m.id == _selectedId);
    } catch (_) {
      return null;
    }
  }

  MeasurementModel? findById(String id) {
    try {
      return _measurements.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns the next colour in the predefined palette that is not yet
  /// used by another measurement; falls back to a random palette colour
  /// if all of them are taken.
  Color getNextColor() {
    if (_measurements.isEmpty) return _availableColors[0];
    final used = _measurements.map((m) => m.color).toSet();
    for (final c in _availableColors) {
      if (!used.contains(c)) return c;
    }
    return _availableColors[math.Random().nextInt(_availableColors.length)];
  }

  // ============================================================
  // Selection + tool
  // ============================================================

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void clearSelection() => select(null);

  void setCurrentTool(MeasurementType type) {
    if (_currentTool == type) return;
    _currentTool = type;
    notifyListeners();
  }

  // ============================================================
  // Primitive list mutations
  // ============================================================

  void addRaw(MeasurementModel m) {
    _measurements.add(m);
    notifyListeners();
  }

  /// Removes the measurement with [id] (if present) and clears the
  /// selection if it pointed at that measurement.
  void removeById(String id) {
    final before = _measurements.length;
    _measurements.removeWhere((m) => m.id == id);
    if (_selectedId == id) _selectedId = null;
    if (_measurements.length != before) notifyListeners();
  }

  /// Removes every measurement whose id is in [ids].
  void removeWhereIdIn(Iterable<String> ids) {
    final set = ids.toSet();
    if (set.isEmpty) return;
    final before = _measurements.length;
    _measurements.removeWhere((m) => set.contains(m.id));
    if (_selectedId != null && set.contains(_selectedId)) _selectedId = null;
    if (_measurements.length != before) notifyListeners();
  }

  // ============================================================
  // Higher-level operations
  // ============================================================

  /// Creates a new measurement of [type] and selects it.
  ///
  /// Returns the new [MeasurementModel], or `null` if the creation was
  /// blocked. Two situations cause `null`:
  ///   1. [type] is calibration and one already exists.
  ///   2. [allowMultipleIncomplete] is `false` (the default) and there
  ///      is already an unfinished measurement of [type]. Set this to
  ///      `true` while a template wizard is driving point placement.
  ///
  /// Callers are responsible for surfacing user-facing feedback for the
  /// blocked case (e.g. a snackbar).
  MeasurementModel? createNew(
    MeasurementType type, {
    String? label,
    List<ReferencePoint>? initialPoints,
    bool forceAcute = false,
    List<String>? sourceIds,
    bool allowMultipleIncomplete = false,
  }) {
    if (type == MeasurementType.calibration && hasCalibration) return null;

    if (!allowMultipleIncomplete) {
      final hasIncomplete = _measurements.any(
        (m) => m.type == type && m.points.length < m.totalSteps,
      );
      if (hasIncomplete) return null;
    }

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final startStep = (initialPoints?.length ?? 0) + 1;

    final m = MeasurementModel(
      id: newId,
      type: type,
      color: type == MeasurementType.calibration
          ? Colors.white
          : getNextColor(),
      activeStep: startStep,
      totalSteps: _totalStepsFor(type),
      label: label,
      forceAcute: forceAcute,
      points: initialPoints,
      sourceIds: sourceIds,
      // Auto-hide the Glenoid Defect helper measurement.
      isAuxiliary: type == MeasurementType.glenoidDefect,
    );

    _measurements.add(m);
    _selectedId = newId;
    _currentTool = type;
    notifyListeners();
    return m;
  }

  static int _totalStepsFor(MeasurementType type) {
    if (type == MeasurementType.spinopelvic ||
        type == MeasurementType.lcea) {
      return 6;
    }
    if (type == MeasurementType.pelvicTilt ||
        type == MeasurementType.pelvicIncidence ||
        type == MeasurementType.cobbAngle ||
        type == MeasurementType.blackburnePeel ||
        type == MeasurementType.glenoidDefect ||
        type == MeasurementType.tonnisAngle) {
      return 4;
    }
    if (type == MeasurementType.modifiedInsallSalvati ||
        type == MeasurementType.angle3Point ||
        type == MeasurementType.circle3Point) {
      return 3;
    }
    if (type == MeasurementType.point) return 1;
    if (type == MeasurementType.areaPolygon) return 99;
    if (type == MeasurementType.distance ||
        type == MeasurementType.calibration ||
        type == MeasurementType.circle ||
        type == MeasurementType.sacralSlope ||
        type == MeasurementType.areaCircle) {
      return 2;
    }
    return 1;
  }

  /// Duplicates the active measurement (offset slightly so the copy is
  /// visible) and selects the duplicate. Returns the new model, or null
  /// if there is no active measurement or it is the calibration object.
  MeasurementModel? duplicateActive() {
    final src = activeMeasurement;
    if (src == null || src.type == MeasurementType.calibration) return null;

    final clone = src.clone();
    const offset = Offset(0.05, 0.05);
    clone.points = clone.points
        .map((p) => ReferencePoint(p.position + offset, label: p.label))
        .toList();
    clone.color = getNextColor();
    if (clone.labelPosition != null) {
      clone.labelPosition = clone.labelPosition! + offset;
    }
    _measurements.add(clone);
    _selectedId = clone.id;
    notifyListeners();
    return clone;
  }

  void undoLastPointOnActive() {
    final m = activeMeasurement;
    if (m == null || m.points.isEmpty || m.isLocked) return;
    m.points.removeLast();
    m.activeStep = m.points.isEmpty ? 1 : m.points.length + 1;
    notifyListeners();
  }

  void toggleLockActive() {
    final m = activeMeasurement;
    if (m == null) return;
    m.isLocked = !m.isLocked;
    notifyListeners();
  }

  /// Closes the active polygon if it has at least 3 points. Returns
  /// `true` on success, `false` if there is no active polygon or it has
  /// fewer than 3 points (caller should display feedback in that case).
  bool finishPolygonActive() {
    final m = activeMeasurement;
    if (m == null || m.type != MeasurementType.areaPolygon) return false;
    if (m.points.length < 3) return false;
    m.isLocked = true;
    _selectedId = null;
    notifyListeners();
    return true;
  }

  // ============================================================
  // Cross-measurement sync
  // ============================================================

  /// Re-projects dependent composite measurements (modified Insall–Salvati,
  /// Blackburne–Peel, Spinopelvic-Tilt/Incidence, Glenoid Defect) so they
  /// follow updates to their source measurements.
  void syncDependents(MeasurementModel source) {
    bool changed = false;

    for (final m in _measurements) {
      final ids = m.sourceIds;
      if (ids == null || !ids.contains(source.id)) continue;

      // Spinopelvic Pattern: SS line + 2 hip centres.
      if ((m.type == MeasurementType.pelvicTilt ||
              m.type == MeasurementType.pelvicIncidence) &&
          ids.length >= 3) {
        try {
          final s1 = _measurements.firstWhere((x) => x.id == ids[0]);
          final s2 = _measurements.firstWhere((x) => x.id == ids[1]);
          final s3 = _measurements.firstWhere((x) => x.id == ids[2]);
          if (s1.points.length >= 2 &&
              s2.points.isNotEmpty &&
              s3.points.isNotEmpty) {
            m.points = [
              ReferencePoint(s1.points[0].position, label: s1.points[0].label),
              ReferencePoint(s1.points[1].position, label: s1.points[1].label),
              ReferencePoint(s2.points[0].position, label: s2.points[0].label),
              ReferencePoint(s3.points[0].position, label: s3.points[0].label),
            ];
            changed = true;
          }
        } catch (_) {}
      }

      // Modified Insall–Salvati: Patella (2 pts) + Tuberosity (1 pt).
      if (m.type == MeasurementType.modifiedInsallSalvati &&
          ids.length >= 2) {
        try {
          final s1 = _measurements.firstWhere((x) => x.id == ids[0]);
          final s2 = _measurements.firstWhere((x) => x.id == ids[1]);
          if (s1.points.length >= 2 && s2.points.isNotEmpty) {
            m.points = [
              ReferencePoint(s1.points[0].position, label: s1.points[0].label),
              ReferencePoint(s1.points[1].position, label: s1.points[1].label),
              ReferencePoint(s2.points[0].position, label: s2.points[0].label),
            ];
            changed = true;
          }
        } catch (_) {}
      }

      // Blackburne–Peel: Patella (2 pts) + Plateau (2 pts).
      if (m.type == MeasurementType.blackburnePeel && ids.length >= 2) {
        try {
          final s1 = _measurements.firstWhere((x) => x.id == ids[0]);
          final s2 = _measurements.firstWhere((x) => x.id == ids[1]);
          if (s1.points.length >= 2 && s2.points.length >= 2) {
            m.points = [
              ReferencePoint(s1.points[0].position, label: s1.points[0].label),
              ReferencePoint(s1.points[1].position, label: s1.points[1].label),
              ReferencePoint(s2.points[0].position, label: s2.points[0].label),
              ReferencePoint(s2.points[1].position, label: s2.points[1].label),
            ];
            changed = true;
          }
        } catch (_) {}
      }

      // Glenoid Defect: Circle (3 pts) + Defect (1 pt).
      if (m.type == MeasurementType.glenoidDefect && ids.length >= 2) {
        try {
          final s1 = _measurements.firstWhere((x) => x.id == ids[0]);
          final s2 = _measurements.firstWhere((x) => x.id == ids[1]);
          if (s1.points.length >= 3 && s2.points.isNotEmpty) {
            m.points = [
              ReferencePoint(s1.points[0].position, label: s1.points[0].label),
              ReferencePoint(s1.points[1].position, label: s1.points[1].label),
              ReferencePoint(s1.points[2].position, label: s1.points[2].label),
              ReferencePoint(s2.points[0].position, label: s2.points[0].label),
            ];
            changed = true;
          }
        } catch (_) {}
      }
    }

    if (changed) notifyListeners();
  }

  // ============================================================
  // Persistence
  // ============================================================

  /// Persists the current record. Pass [activeTemplateId] when a template
  /// is currently active so it survives reloads.
  Future<void> autoSave({String? activeTemplateId}) async {
    _record.measurements = List.from(_measurements);
    if (activeTemplateId != null) {
      _record.templateId = activeTemplateId;
    }
    if (_measurements.isNotEmpty || !_record.isAutoSaved) {
      await _historyService.saveRecord(_record);
    }
  }

  /// Copies [originalPath] into the app's documents directory if it isn't
  /// already there, then updates [record.imagePath] and persists the
  /// record. iOS sandboxing in particular requires this so re-launching
  /// the app can still find the image.
  Future<void> persistImage(String originalPath) async {
    try {
      final file = File(originalPath);
      if (!await file.exists()) return;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName = originalPath.split('/').last;
      final persistentPath = '${appDir.path}/$fileName';

      if (originalPath.startsWith(appDir.path)) {
        _record.imagePath = originalPath;
        notifyListeners();
        return;
      }

      final targetFile = File(persistentPath);
      if (!await targetFile.exists()) {
        await file.copy(persistentPath);
        debugPrint('Image persisted to: $persistentPath');
      }

      _record.imagePath = persistentPath;
      notifyListeners();
      await _historyService.saveRecord(_record);
    } catch (e) {
      debugPrint('Error persisting image: $e');
    }
  }

  void setRecordTemplateId(String? id) {
    if (_record.templateId == id) return;
    _record.templateId = id;
    notifyListeners();
  }
}
