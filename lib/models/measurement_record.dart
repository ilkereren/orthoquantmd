import 'package:ortho_quant_md/models/measurement_model.dart';

class MeasurementRecord {
  final String id;
  final DateTime timestamp;
  String imagePath;
  List<MeasurementModel> measurements;
  String? patientName;
  String? patientId;
  String? notes;
  bool isAutoSaved;
  int schemaVersion; // For future migrations
  String? templateId; // ID of the active template if any
  String? groupId; // ID of the group this record belongs to

  MeasurementRecord({
    required this.id,
    required this.timestamp,
    required this.imagePath,
    required this.measurements,
    this.patientName,
    this.patientId,
    this.notes,
    this.isAutoSaved = true,
    this.schemaVersion = 1,
    this.templateId,
    this.groupId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'imagePath': imagePath,
      'measurements': measurements.map((m) => m.toJson()).toList(),
      'patientName': patientName,
      'patientId': patientId,
      'notes': notes,
      'isAutoSaved': isAutoSaved,
      'schemaVersion': schemaVersion,
      'templateId': templateId,
      'groupId': groupId,
    };
  }

  static MeasurementRecord fromJson(Map<String, dynamic> json) {
    return MeasurementRecord(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      imagePath: json['imagePath'],
      measurements: (json['measurements'] as List)
          .map((m) => MeasurementModel.fromJson(m))
          .toList(),
      patientName: json['patientName'],
      patientId: json['patientId'],
      notes: json['notes'],
      isAutoSaved: json['isAutoSaved'] ?? true,
      schemaVersion: json['schemaVersion'] ?? 0, // 0 implies legacy/pre-versioning
      templateId: json['templateId'],
      groupId: json['groupId'],
    );
  }
}

