import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ortho_quant_md/models/measurement_record.dart';
import 'package:ortho_quant_md/models/history_group.dart';

class HistoryService {
  static const String _fileName = 'ortho_history.json';
  static const String _groupsFileName = 'ortho_groups.json';

  Future<File> get _file async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<File> get _groupsFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_groupsFileName');
  }

  // --- Groups Support ---

  Future<List<HistoryGroup>> getGroups() async {
    try {
      final file = await _groupsFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => HistoryGroup.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveGroup(HistoryGroup group) async {
    final groups = await getGroups();
    final index = groups.indexWhere((g) => g.id == group.id);
    if (index != -1) {
      groups[index] = group;
    } else {
      groups.add(group);
    }
    await _writeGroups(groups);
  }

  Future<bool> deleteGroup(String id) async {
    final records = await getRecords();
    final hasRecords = records.any((r) => r.groupId == id);
    if (hasRecords) return false; // Blocking deletion of non-empty group

    final groups = await getGroups();
    groups.removeWhere((g) => g.id == id);
    await _writeGroups(groups);
    return true;
  }

  Future<void> _writeGroups(List<HistoryGroup> groups) async {
    final file = await _groupsFile;
    final jsonList = groups.map((g) => g.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<void> updateRecordGroup(String recordId, String? groupId) async {
    final records = await getRecords();
    final index = records.indexWhere((r) => r.id == recordId);
    if (index != -1) {
      records[index].groupId = groupId;
      await _writeRecords(records);
    }
  }

  // --- Records Support ---

  Future<List<MeasurementRecord>> getRecords() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      
      final records = jsonList.map((j) {
        try {
          return MeasurementRecord.fromJson(j);
        } catch (e) {
          print('Error parsing record: $e');
          return null; // Skip malformed
        }
      })
      .whereType<MeasurementRecord>() // Filter nulls
      .toList();
      
      // Attempt to heal broken paths (iOS Sandbox Rotation)
      bool needsSave = false;
      final directory = await getApplicationDocumentsDirectory();
      
      for (var record in records) {
          final file = File(record.imagePath);
          if (!await file.exists()) {
             // Try to find file in current documents dir with same name
             final fileName = record.imagePath.split('/').last;
             final newPath = '${directory.path}/$fileName';
             final newFile = File(newPath);
             
             if (await newFile.exists()) {
                 print('Healed path for ${record.id}: ${record.imagePath} -> $newPath');
                 record.imagePath = newPath; // Update object in memory
                 needsSave = true;
             }
          }
      }
      
      if (needsSave) {
         await _writeRecords(records); // Persist repaired paths
      }
      
      return records;
    } catch (e) {
      // Return empty list on corruption or error
      return [];
    }
  }

  Future<void> saveRecord(MeasurementRecord record) async {
    final records = await getRecords();
    
    // Check if exists to update, else add top
    final index = records.indexWhere((r) => r.id == record.id);
    if (index != -1) {
      records[index] = record;
    } else {
      records.insert(0, record);
      // Increment lifetime counter for new records
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt('lifetime_exams') ?? 0;
      await prefs.setInt('lifetime_exams', count + 1);
    }
    
    await _writeRecords(records);
  }
  
  Future<void> deleteRecord(String id) async {
    final records = await getRecords();
    records.removeWhere((r) => r.id == id);
    await _writeRecords(records);
  }

  Future<void> _writeRecords(List<MeasurementRecord> records) async {
    final file = await _file;
    final jsonList = records.map((r) => r.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<Map<String, int>> getAppUsageStatistics() async {
    int totalSize = 0;
    int totalExams = 0;
    int lifetimeExams = 0;
    int totalMeasurements = 0;

    try {
      final records = await getRecords();
      totalExams = records.length;
      
      final prefs = await SharedPreferences.getInstance();
      lifetimeExams = prefs.getInt('lifetime_exams') ?? 0;
      
      // Sync lifetime if it's somehow less than current (initial run case)
      if (lifetimeExams < totalExams) {
        lifetimeExams = totalExams;
        await prefs.setInt('lifetime_exams', lifetimeExams);
      }

      // 1. History File Size
      final file = await _file;
      if (await file.exists()) {
        totalSize += await file.length();
      }

      // 2. Images Size & Measurement Counts
      for (var record in records) {
        totalMeasurements += record.measurements.length;
        
        final imageFile = File(record.imagePath);
        if (await imageFile.exists()) {
          totalSize += await imageFile.length();
        }
      }
    } catch (e) {
      // Ignore errors for stats
    }

    return {
      'storage': totalSize,
      'exams': totalExams,
      'lifetime_exams': lifetimeExams,
      'measurements': totalMeasurements,
    };
  }
}
