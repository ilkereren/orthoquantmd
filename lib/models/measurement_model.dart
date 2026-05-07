
import 'package:flutter/services.dart';

enum MeasurementType {
  angle3Point,
  cobbAngle, // 4 points (2 lines)
  distance,
  calibration, // New type for global scaling
  circle, // Center point + radius point
  spinopelvic, // SS, PT, PI composite
  sacralSlope, // 2 points (Line with Horiz)
  pelvicTilt, // 4 points (S1 line, 2 Hip Centers)
  pelvicIncidence, // 4 points (S1 line, 2 Hip Centers)
  point, // Single point marker
  blackburnePeel, // 4 points (Patella Sup-Inf, Plateau Post-Ant)
  modifiedInsallSalvati, // 3 points (Patella Sup-Inf, Tuberosity)
  circle3Point, // 3 points on circumference
  glenoidDefect, // Calculation: Circle + Defect Point
  acromialIndex, // Glenoid Plane distances ratio
  talonavicularCoverage, // Angle between articular surfaces
  talonavicularUncoverage, // Percentage of uncoverage
  talarIncongruency, // Angle between lateral articular and lateral talar neck
  calcanealPitch, // Angle between Calcaneus Inf and Horizontal
  talocalcanealAngle, // Angle between Talus Axis and Calcaneus Axis
  areaCircle, // 3 points on circumference, calculates area
  areaPolygon, // Variable points (3+), finish button closes shape

  glenoidVersion, // Friedman method: Scapula Medial, Glenoid Ant, Glenoid Post
  lcea, // Lateral Center-Edge Angle
  tonnisAngle, // Acetabular Index
  crossoverSign, // Anterior vs Posterior Wall
  posteriorWallSign, // Posterior Wall vs Center
  
  // Hand/Wrist
  ulnarVariance, // Vertical distance between Distal Ulna and Distal Radius
  radialInclination, // Angle of distal radius inclination
  radialHeight, // Vertical height of Radial Styloid relative to Lunate Fossa
  
  // Carpal Sagittal
  scapholunateAngle, // Angle between Scaphoid and Lunate axes
  capitolunateAngle, // Angle between Capitate and Lunate axes
  volarTilt, // Distal Radius Volar Tilt

  // Knee Arthroplasty
  kneeSagittalBalance,
  
  // Lower Limb
  lowerLimbDeformity, // FTA, MAD, aLDFA, aMPTA, JLCA
}

class ReferencePoint {
  final Offset position;
  final String label;

  ReferencePoint(this.position, {this.label = ''});
}

class MeasurementModel {
  final String id;
  MeasurementType type;
  List<ReferencePoint> points;
  final DeviceOrientation? deviceOrientation;
  Color color;
  bool isLocked;
  int activeStep;
  int totalSteps;
  Offset? labelPosition;
  double? calibrationValue; // Real-world length in mm for calibration objects
  String? label; // Custom label (e.g. HVA, IMA)
  bool forceAcute; // Always show acute angle
  List<String>? sourceIds; // IDs of measurements this one depends on (for auto-update)
  bool isAuxiliary; // If true, not listed in UI and not selectable
  bool isDashed;
  bool isInfinite;
  bool isTemplateResult;

  MeasurementModel({
    required this.id,
    this.type = MeasurementType.angle3Point,
    List<ReferencePoint>? points,
    this.deviceOrientation,
    this.color = const Color(0xFF00BFA5),
    this.isLocked = false,
    this.activeStep = 1,
    this.totalSteps = 1,
    this.labelPosition,
    this.calibrationValue,
    this.label,
    this.forceAcute = false,
    this.sourceIds,
    this.isAuxiliary = false, // Default false
    this.isDashed = false,
    this.isInfinite = false,
    this.isTemplateResult = false,
  }) : points = points ?? [];

  MeasurementModel clone() {
    return MeasurementModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      points: List.from(points),
      deviceOrientation: deviceOrientation,
      color: color,
      isLocked: isLocked,
      activeStep: activeStep,
      totalSteps: totalSteps,
      labelPosition: labelPosition,
      calibrationValue: calibrationValue,
      label: label,
      forceAcute: forceAcute,
      sourceIds: sourceIds != null ? List.from(sourceIds!) : null,
      isAuxiliary: isAuxiliary,
      isDashed: isDashed,
      isInfinite: isInfinite,
      isTemplateResult: isTemplateResult,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name, // Use name instead of index for robustness
      'points': points.map((p) => {
        'x': p.position.dx,
        'y': p.position.dy,
        'label': p.label
      }).toList(),
      'color': color.toARGB32(),
      'isLocked': isLocked,
      'activeStep': activeStep,
      'totalSteps': totalSteps,
      'labelPosition': labelPosition != null ? {'x': labelPosition!.dx, 'y': labelPosition!.dy} : null,
      'calibrationValue': calibrationValue,
      'label': label,
      'forceAcute': forceAcute,
      'sourceIds': sourceIds,
      'isAuxiliary': isAuxiliary,
      'isDashed': isDashed,
      'isInfinite': isInfinite,
      'isTemplateResult': isTemplateResult,
    };
  }

  static MeasurementModel fromJson(Map<String, dynamic> json) {
    MeasurementType parsedType;
    final typeData = json['type'];
    if (typeData is int) {
      // Legacy: Integer index
      parsedType = MeasurementType.values[typeData];
    } else if (typeData is String) {
      // New: String name
      parsedType = MeasurementType.values.firstWhere(
        (e) => e.name == typeData, 
        orElse: () => MeasurementType.angle3Point // Fallback
      );
    } else {
      parsedType = MeasurementType.angle3Point;
    }

    return MeasurementModel(
      id: json['id'],
      type: parsedType,
      points: (json['points'] as List).map((p) => ReferencePoint(
        Offset(p['x'], p['y']),
        label: p['label'] ?? '',
      )).toList(),
      color: Color(json['color']),
      isLocked: json['isLocked'] ?? false,
      activeStep: json['activeStep'] ?? 1,
      totalSteps: json['totalSteps'] ?? 1,
      labelPosition: json['labelPosition'] != null ? Offset(json['labelPosition']['x'], json['labelPosition']['y']) : null,
      calibrationValue: json['calibrationValue'],
      label: json['label'],
      forceAcute: json['forceAcute'] ?? false,
      sourceIds: json['sourceIds'] != null ? List<String>.from(json['sourceIds']) : null,
      isAuxiliary: json['isAuxiliary'] ?? false,
      isDashed: json['isDashed'] ?? false,
      isInfinite: json['isInfinite'] ?? false,
      isTemplateResult: json['isTemplateResult'] ?? false,
    );
  }
}
