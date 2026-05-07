
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // Keys
  static const String kStyleTextBoldKey = 'style_text_bold';
  static const String kStyleTextSizeKey = 'style_text_size';
  static const String kStyleLineThicknessKey = 'style_line_thickness';
  static const String kStyleLandmarkSizeKey = 'style_landmark_size';
  static const String kAutoZoomEnabledKey = 'auto_zoom_enabled';

  // State
  bool _textBold = false;
  double _textSize = 20.0; // Default 20
  double _lineThickness = 5.0; // Default to mid-range
  double _landmarkSize = 2.0; // Default 2.0 (Small) per user request
  bool _autoZoomEnabled = true;

  // Getters
  bool get textBold => _textBold;
  double get textSize => _textSize;
  double get lineThickness => _lineThickness;
  double get landmarkSize => _landmarkSize;
  bool get autoZoomEnabled => _autoZoomEnabled;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _textBold = prefs.getBool(kStyleTextBoldKey) ?? false;
    _textSize = prefs.getDouble(kStyleTextSizeKey) ?? 14.0;
    _lineThickness = prefs.getDouble(kStyleLineThicknessKey) ?? 2.0;
    _landmarkSize = prefs.getDouble(kStyleLandmarkSizeKey) ?? 2.0;
    _autoZoomEnabled = prefs.getBool(kAutoZoomEnabledKey) ?? true;
    notifyListeners();
  }

  Future<void> updateTextBold(bool value) async {
    _textBold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kStyleTextBoldKey, value);
    notifyListeners();
  }

  Future<void> updateTextSize(double value) async {
    _textSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kStyleTextSizeKey, value);
  }

  Future<void> updateLineThickness(double value) async {
    _lineThickness = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kStyleLineThicknessKey, value);
  }

  Future<void> updateLandmarkSize(double value) async {
    _landmarkSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kStyleLandmarkSizeKey, value);
  }

  Future<void> setAutoZoomEnabled(bool value) async {
    _autoZoomEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoZoomEnabledKey, value);
  }
}
