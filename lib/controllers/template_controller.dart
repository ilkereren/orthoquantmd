import 'package:flutter/material.dart';

import 'package:ortho_quant_md/controllers/measurement_controller.dart';
import 'package:ortho_quant_md/models/measurement_model.dart';
import 'package:ortho_quant_md/models/template_model.dart';
import 'package:ortho_quant_md/templates/base/measurement_template_base.dart';
import 'package:ortho_quant_md/templates/template_registry.dart';
import 'package:ortho_quant_md/utils/geometry.dart';

/// Owns the active template wizard state for MeasurementScreen.
///
/// This first slice intentionally mirrors the old screen fields so the
/// refactor can proceed without changing template behavior in one large jump.
/// The screen still performs some template operations directly through proxy
/// getters; subsequent slices will move those methods here.
class TemplateController extends ChangeNotifier {
  TemplateController(this._measurementCtrl);

  final MeasurementController _measurementCtrl;

  MeasurementTemplate? _activeTemplate;
  MeasurementTemplateBase? _activeModularTemplate;
  List<String> _modularResults = [];
  int _activeLandmarkIndex = 0;
  final Map<String, String> _templateLandmarkMeasurementIds = {};
  final Map<String, String> _templateCalculationIds = {};

  MeasurementTemplate? get activeTemplate => _activeTemplate;
  MeasurementTemplateBase? get activeModularTemplate => _activeModularTemplate;
  List<String> get modularResults => _modularResults;
  int get activeLandmarkIndex => _activeLandmarkIndex;
  Map<String, String> get templateLandmarkMeasurementIds =>
      _templateLandmarkMeasurementIds;
  Map<String, String> get templateCalculationIds => _templateCalculationIds;

  bool isTemplateMeasurement(String id) {
    return _templateLandmarkMeasurementIds.containsValue(id) ||
        _templateCalculationIds.containsValue(id);
  }

  Set<String> get trackedMeasurementIds => {
    ..._templateLandmarkMeasurementIds.values,
    ..._templateCalculationIds.values,
  };

  void activateBridge(MeasurementTemplate? template) {
    _activeTemplate = template;
    _activeModularTemplate = template == null
        ? null
        : TemplateRegistry.getById(template.id);
  }

  void setActiveLandmarkIndexBridge(int index) {
    _activeLandmarkIndex = index;
  }

  void setModularResultsBridge(List<String> results) {
    _modularResults = results;
  }

  void clearModularResultsBridge() {
    _modularResults.clear();
  }

  void resetForTemplateBridge(MeasurementTemplate template) {
    _activeTemplate = template;
    _activeModularTemplate = TemplateRegistry.getById(template.id);
    _modularResults.clear();
    _activeLandmarkIndex = 0;
    _templateLandmarkMeasurementIds.clear();
    _templateCalculationIds.clear();
  }

  void clearBridge() {
    _activeTemplate = null;
    _activeModularTemplate = null;
    _modularResults.clear();
    _activeLandmarkIndex = 0;
    _templateLandmarkMeasurementIds.clear();
    _templateCalculationIds.clear();
  }

  void restore(MeasurementTemplate template) {
    _activeTemplate = template;
    _activeModularTemplate = TemplateRegistry.getById(template.id);
    _modularResults.clear();
    _activeLandmarkIndex = template.landmarks.length; // Assume complete.
    _templateLandmarkMeasurementIds.clear();
    _templateCalculationIds.clear();

    for (final lm in template.landmarks) {
      try {
        final m = _measurementCtrl.measurements.firstWhere(
          (x) => x.type == MeasurementType.point && x.label == lm.label,
        );
        _templateLandmarkMeasurementIds[lm.id] = m.id;
      } catch (_) {}
    }

    for (final calc in template.calculations) {
      try {
        final mCandidates = _measurementCtrl.measurements
            .where((x) => x.label == calc.label)
            .toList();
        if (mCandidates.isNotEmpty) {
          _templateCalculationIds[calc.id] = mCandidates.first.id;
        } else {
          final mTypeCandidates = _measurementCtrl.measurements
              .where(
                (x) => x.type == calc.type && x.isAuxiliary == calc.isAuxiliary,
              )
              .toList();
          if (mTypeCandidates.length == 1) {
            _templateCalculationIds[calc.id] = mTypeCandidates.first.id;
          }
        }
      } catch (_) {}
    }

    if (template.id == 'glenoid_bone_loss') {
      try {
        final m = _measurementCtrl.measurements.firstWhere(
          (x) => x.type == MeasurementType.glenoidDefect,
        );
        _templateCalculationIds['gbl_percent'] = m.id;
        _templateCalculationIds['gbl_size'] = m.id;
      } catch (_) {}
    }

    if (template.id == 'glenoid_version') {
      try {
        final m = _measurementCtrl.measurements.firstWhere(
          (x) => x.type == MeasurementType.glenoidVersion,
        );
        for (final c in template.calculations) {
          _templateCalculationIds[c.id] = m.id;
        }
      } catch (_) {}
    }

    syncMeasurements();
    notifyListeners();
  }

  bool syncMeasurements() {
    final activeTemplate = _activeTemplate;
    if (activeTemplate == null) return false;

    bool changed = false;
    final measurements = _measurementCtrl.measurements;

    for (final calc in activeTemplate.calculations) {
      final points = <ReferencePoint>[];
      bool missing = false;
      for (final lmId in calc.landmarkIds) {
        final mId = _templateLandmarkMeasurementIds[lmId];
        if (mId == null) {
          missing = true;
          break;
        }
        final landmarkM = _measurementCtrl.findById(mId);
        if (landmarkM == null || landmarkM.points.isEmpty) {
          missing = true;
          break;
        }
        points.add(landmarkM.points.first);
      }

      if (missing) continue;

      final existingId = _templateCalculationIds[calc.id];
      MeasurementModel? m = existingId == null
          ? null
          : _measurementCtrl.findById(existingId);

      bool isNew = false;
      if (m == null) {
        final newId =
            DateTime.now().millisecondsSinceEpoch.toString() + calc.id;
        m = MeasurementModel(
          id: newId,
          type: calc.type,
          color: Colors.yellowAccent,
          activeStep: points.length,
          totalSteps: points.length,
          points: List.from(points),
          label: calc.label,
          forceAcute: calc.forceAcute,
          isLocked: false,
          isAuxiliary: calc.isAuxiliary,
          isTemplateResult: true,
        );
        _templateCalculationIds[calc.id] = newId;
        isNew = true;
      }

      m.points = List.from(points);

      if (activeTemplate.id == 'glenoid_planning_ap') {
        _applyGlenoidPlanningLogic(calc, m);
      }

      if (isNew) {
        measurements.add(m);
        changed = true;
      }
    }

    if (changed) notifyListeners();
    return changed;
  }

  void activate(MeasurementTemplate template) {
    if (template.landmarks.isEmpty) return;

    resetForTemplateBridge(template);

    final lm = template.landmarks.first;
    _measurementCtrl.createNew(
      MeasurementType.point,
      label: lm.label,
      allowMultipleIncomplete: true,
    );

    final selectedId = _measurementCtrl.selectedId;
    if (selectedId != null) {
      _templateLandmarkMeasurementIds[lm.id] = selectedId;
    }
    notifyListeners();
  }

  void clearActiveTemplateMeasurements() {
    _measurementCtrl.removeWhereIdIn(trackedMeasurementIds);
    clearBridge();
    notifyListeners();
  }

  void _applyGlenoidPlanningLogic(
    TemplateCalculation calc,
    MeasurementModel m,
  ) {
    if (calc.id == 'ss_fossa_line') {
      m.isDashed = true;
      m.isInfinite = true;
      m.color = Colors.cyanAccent;
      return;
    }

    if (calc.id != 'perp_c_line' && calc.id != 'rsa' && calc.id != 'asa') {
      return;
    }

    final aId = _templateLandmarkMeasurementIds['ss_med'];
    final bId = _templateLandmarkMeasurementIds['ss_lat'];
    final cId = _templateLandmarkMeasurementIds['gl_inf'];

    if (aId == null || bId == null || cId == null) return;

    final a = _measurementCtrl.findById(aId);
    final b = _measurementCtrl.findById(bId);
    final c = _measurementCtrl.findById(cId);
    if (a == null ||
        b == null ||
        c == null ||
        a.points.isEmpty ||
        b.points.isEmpty ||
        c.points.isEmpty) {
      return;
    }

    final pA = a.points.first.position;
    final pB = b.points.first.position;
    final pC = c.points.first.position;
    final pX = GeometryUtils.projectPointToLine(pC, pA, pB);

    if (calc.id == 'perp_c_line') {
      m.points = [ReferencePoint(pX), ReferencePoint(pC)];
      m.isDashed = true;
      m.isInfinite = true;
      m.color = Colors.cyanAccent;
    } else if (m.points.isNotEmpty) {
      m.points[0] = ReferencePoint(pX);
    }
  }
}
