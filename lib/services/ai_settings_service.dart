import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

enum AiProvider {
  openai('OpenAI'),
  gemini('Gemini'),
  claude('Claude');

  const AiProvider(this.label);

  final String label;

  static AiProvider fromName(String? name) {
    return AiProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => AiProvider.openai,
    );
  }
}

enum AiKeyMode {
  orthoQuantKey('Use OrthoQuant Key'),
  ownKey('Use my own API key');

  const AiKeyMode(this.label);

  final String label;

  static AiKeyMode fromName(String? name) {
    return AiKeyMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => AiKeyMode.orthoQuantKey,
    );
  }
}

class AiModelInfo {
  const AiModelInfo({required this.id, this.displayName});

  final String id;
  final String? displayName;

  String get label {
    final name = displayName?.trim();
    if (name == null || name.isEmpty || name == id) return id;
    return '$name ($id)';
  }
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.keyMode,
    required this.apiKey,
    required this.model,
  });

  final AiProvider provider;
  final AiKeyMode keyMode;
  final String apiKey;
  final String model;

  String get effectiveApiKey {
    if (keyMode == AiKeyMode.orthoQuantKey) {
      return '';
    }
    return apiKey;
  }
}

class AiSettingsService {
  static const String kProviderKey = 'ai_provider';
  static const String kKeyModeKey = 'ai_key_mode';
  static const String kApiKeyKey = 'ai_api_key';
  static const String kModelKey = 'ai_model';
  static const String kInstallationIdKey = 'ai_installation_id';
  static const String kOrthoQuantUsageWeekKey = 'ai_orthoquant_usage_week';
  static const String kOrthoQuantUsageCountKey = 'ai_orthoquant_usage_count';
  static const Duration _modelListTimeout = Duration(seconds: 20);
  static const int orthoQuantWeeklyLimit = 10;
  static const AiProvider orthoQuantProvider = AiProvider.openai;
  static const String orthoQuantModel = 'gpt-5.4-mini';
  static const String orthoQuantProxyUrl = String.fromEnvironment(
    'ORTHOQUANT_AI_PROXY_URL',
    defaultValue: '',
  );

  Future<AiSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final keyMode = AiKeyMode.fromName(prefs.getString(kKeyModeKey));
    return AiSettings(
      provider: AiProvider.fromName(prefs.getString(kProviderKey)),
      keyMode: keyMode,
      apiKey: prefs.getString(kApiKeyKey) ?? '',
      model: prefs.getString(kModelKey) ?? '',
    );
  }

  Future<void> saveSettings({
    required AiProvider provider,
    required AiKeyMode keyMode,
    required String apiKey,
    required String model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kProviderKey, provider.name);
    await prefs.setString(kKeyModeKey, keyMode.name);
    await prefs.setString(kApiKeyKey, apiKey.trim());
    await prefs.setString(kModelKey, model.trim());
  }

  Future<int> getOrthoQuantRemainingUses() async {
    await _resetOrthoQuantUsageIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(kOrthoQuantUsageCountKey) ?? 0;
    return (orthoQuantWeeklyLimit - used).clamp(0, orthoQuantWeeklyLimit);
  }

  DateTime getOrthoQuantResetDate() {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    return monday.add(const Duration(days: 7));
  }

  Future<void> _assertOrthoQuantQuotaAvailable() async {
    final remaining = await getOrthoQuantRemainingUses();
    if (remaining <= 0) {
      final resetDate = _formatDate(getOrthoQuantResetDate());
      throw AiSettingsException(
        'Weekly OrthoQuant AI limit reached. Your quota resets on $resetDate.',
      );
    }
  }

  Future<void> _incrementOrthoQuantUsage() async {
    await _resetOrthoQuantUsageIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(kOrthoQuantUsageCountKey) ?? 0;
    await prefs.setInt(kOrthoQuantUsageCountKey, used + 1);
  }

  Future<void> _resetOrthoQuantUsageIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final currentWeek = _currentUsageWeekId();
    if (prefs.getString(kOrthoQuantUsageWeekKey) != currentWeek) {
      await prefs.setString(kOrthoQuantUsageWeekKey, currentWeek);
      await prefs.setInt(kOrthoQuantUsageCountKey, 0);
    }
  }

  String _currentUsageWeekId() {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  Future<List<AiModelInfo>> fetchModels({
    required AiProvider provider,
    required String apiKey,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const AiSettingsException(
        'Enter an API key before loading models.',
      );
    }

    try {
      switch (provider) {
        case AiProvider.openai:
          return _fetchOpenAiModels(key);
        case AiProvider.gemini:
          return _fetchGeminiModels(key);
        case AiProvider.claude:
          return _fetchClaudeModels(key);
      }
    } on AiSettingsException {
      rethrow;
    } on TimeoutException {
      throw const AiSettingsException(
        'Model list request timed out. Check the API key and network connection.',
      );
    } catch (e) {
      throw AiSettingsException(
        'Could not load models. On web builds, direct provider calls can be blocked by browser CORS rules. Details: $e',
      );
    }
  }

  Future<void> testModel({
    required AiProvider provider,
    required String apiKey,
    required String model,
  }) async {
    final key = apiKey.trim();
    final selectedModel = model.trim();
    if (key.isEmpty) {
      throw const AiSettingsException('Enter an API key before testing model.');
    }
    if (selectedModel.isEmpty) {
      throw const AiSettingsException('Select a model before testing.');
    }

    try {
      switch (provider) {
        case AiProvider.openai:
          await _testOpenAiModel(key, selectedModel);
        case AiProvider.gemini:
          await _testGeminiModel(key, selectedModel);
        case AiProvider.claude:
          await _testClaudeModel(key, selectedModel);
      }
    } on AiSettingsException {
      rethrow;
    } on TimeoutException {
      throw const AiSettingsException(
        'Model test request timed out. Check the model, API key, and network connection.',
      );
    } catch (e) {
      throw AiSettingsException(
        'Could not test model. On web builds, direct provider calls can be blocked by browser CORS rules. Details: $e',
      );
    }
  }

  Future<String> generateClinicalInterpretation({
    required AiProvider provider,
    required AiKeyMode keyMode,
    required String apiKey,
    required String model,
    required String templateTitle,
    required List<Map<String, String>> results,
  }) async {
    final key = apiKey.trim();
    final selectedModel = keyMode == AiKeyMode.orthoQuantKey
        ? orthoQuantModel
        : model.trim();
    if (keyMode == AiKeyMode.orthoQuantKey && orthoQuantProxyUrl.isEmpty) {
      throw const AiSettingsException(
        'OrthoQuant AI proxy is not configured in this build.',
      );
    }
    if (keyMode == AiKeyMode.ownKey && key.isEmpty) {
      throw const AiSettingsException(
        'AI provider, API key, and model must be configured in Settings first.',
      );
    }
    if (selectedModel.isEmpty) {
      throw const AiSettingsException(
        'AI provider, API key, and model must be configured in Settings first.',
      );
    }
    if (results.isEmpty) {
      throw const AiSettingsException(
        'There are no template results to interpret yet.',
      );
    }

    final prompt = _buildClinicalInterpretationPrompt(
      templateTitle: templateTitle,
      results: results,
    );

    try {
      if (keyMode == AiKeyMode.orthoQuantKey) {
        await _assertOrthoQuantQuotaAvailable();
      }
      late final String text;
      if (keyMode == AiKeyMode.orthoQuantKey) {
        text = await _generateOrthoQuantProxyText(
          templateTitle: templateTitle,
          results: results,
        );
      } else {
        switch (provider) {
          case AiProvider.openai:
            text = await _generateOpenAiText(key, selectedModel, prompt);
          case AiProvider.gemini:
            text = await _generateGeminiText(key, selectedModel, prompt);
          case AiProvider.claude:
            text = await _generateClaudeText(key, selectedModel, prompt);
        }
      }
      if (keyMode == AiKeyMode.orthoQuantKey) {
        await _incrementOrthoQuantUsage();
      }
      return text;
    } on AiSettingsException {
      rethrow;
    } on TimeoutException {
      throw const AiSettingsException(
        'AI interpretation request timed out. Check the model, API key, and network connection.',
      );
    } catch (e) {
      throw AiSettingsException(
        'Could not generate interpretation. On web builds, direct provider calls can be blocked by browser CORS rules. Details: $e',
      );
    }
  }

  Future<List<AiModelInfo>> _fetchOpenAiModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final data = body['data'];
    if (data is! List) return const [];

    final models =
        data
            .whereType<Map<String, dynamic>>()
            .map((item) => AiModelInfo(id: item['id']?.toString() ?? ''))
            .where((model) => model.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  Future<List<AiModelInfo>> _fetchGeminiModels(String apiKey) async {
    final response = await http
        .get(
          Uri.https('generativelanguage.googleapis.com', '/v1beta/models', {
            'key': apiKey,
          }),
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final data = body['models'];
    if (data is! List) return const [];

    final models =
        data
            .whereType<Map<String, dynamic>>()
            .where((item) {
              final methods = item['supportedGenerationMethods'];
              return methods is List && methods.contains('generateContent');
            })
            .map((item) {
              final rawName = item['name']?.toString() ?? '';
              final id = rawName.startsWith('models/')
                  ? rawName.substring('models/'.length)
                  : rawName;
              return AiModelInfo(
                id: id,
                displayName: item['displayName']?.toString(),
              );
            })
            .where((model) => model.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  Future<List<AiModelInfo>> _fetchClaudeModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('https://api.anthropic.com/v1/models'),
          headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final data = body['data'];
    if (data is! List) return const [];

    final models =
        data
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => AiModelInfo(
                id: item['id']?.toString() ?? '',
                displayName: item['display_name']?.toString(),
              ),
            )
            .where((model) => model.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  Future<void> _testOpenAiModel(String apiKey, String model) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/responses'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'input': 'Reply with OK.',
            'max_output_tokens': 8,
          }),
        )
        .timeout(_modelListTimeout);
    _decodeResponse(response);
  }

  Future<void> _testGeminiModel(String apiKey, String model) async {
    final response = await http
        .post(
          Uri.https(
            'generativelanguage.googleapis.com',
            '/v1beta/models/$model:generateContent',
            {'key': apiKey},
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Reply with OK.'},
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': 8},
          }),
        )
        .timeout(_modelListTimeout);
    _decodeResponse(response);
  }

  Future<void> _testClaudeModel(String apiKey, String model) async {
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 8,
            'messages': [
              {'role': 'user', 'content': 'Reply with OK.'},
            ],
          }),
        )
        .timeout(_modelListTimeout);
    _decodeResponse(response);
  }

  Future<String> _generateOpenAiText(
    String apiKey,
    String model,
    String prompt,
  ) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/responses'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'input': prompt,
            'max_output_tokens': 700,
          }),
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final outputText = body['output_text']?.toString().trim();
    if (outputText != null && outputText.isNotEmpty) return outputText;

    final output = body['output'];
    if (output is List) {
      final chunks = <String>[];
      for (final item in output.whereType<Map<String, dynamic>>()) {
        final content = item['content'];
        if (content is List) {
          for (final part in content.whereType<Map<String, dynamic>>()) {
            final text = part['text']?.toString();
            if (text != null && text.trim().isNotEmpty) chunks.add(text);
          }
        }
      }
      final joined = chunks.join('\n').trim();
      if (joined.isNotEmpty) return joined;
    }
    throw const AiSettingsException('The model returned an empty response.');
  }

  Future<String> _generateGeminiText(
    String apiKey,
    String model,
    String prompt,
  ) async {
    final response = await http
        .post(
          Uri.https(
            'generativelanguage.googleapis.com',
            '/v1beta/models/$model:generateContent',
            {'key': apiKey},
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': 700},
          }),
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final candidates = body['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = candidates.first['content'];
      if (content is Map<String, dynamic>) {
        final parts = content['parts'];
        if (parts is List) {
          final text = parts
              .whereType<Map<String, dynamic>>()
              .map((part) => part['text']?.toString() ?? '')
              .where((text) => text.trim().isNotEmpty)
              .join('\n')
              .trim();
          if (text.isNotEmpty) return text;
        }
      }
    }
    throw const AiSettingsException('The model returned an empty response.');
  }

  Future<String> _generateClaudeText(
    String apiKey,
    String model,
    String prompt,
  ) async {
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 700,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final content = body['content'];
    if (content is List) {
      final text = content
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.trim().isNotEmpty)
          .join('\n')
          .trim();
      if (text.isNotEmpty) return text;
    }
    throw const AiSettingsException('The model returned an empty response.');
  }

  Future<String> _generateOrthoQuantProxyText({
    required String templateTitle,
    required List<Map<String, String>> results,
  }) async {
    final installationId = await _getInstallationId();
    final response = await http
        .post(
          Uri.parse(orthoQuantProxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'installationId': installationId,
            'templateTitle': templateTitle,
            'results': results,
          }),
        )
        .timeout(_modelListTimeout);
    final body = _decodeResponse(response);
    final text = body['text']?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    throw const AiSettingsException('The model returned an empty response.');
  }

  Future<String> _getInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(kInstallationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(kInstallationIdKey, id);
    return id;
  }

  String _buildClinicalInterpretationPrompt({
    required String templateTitle,
    required List<Map<String, String>> results,
  }) {
    final formattedResults = results
        .map((item) {
          final label = item['label']?.trim() ?? 'Measurement';
          final value = item['value']?.trim() ?? '';
          return '- $label: $value';
        })
        .join('\n');

    return '''
You are assisting an orthopedic clinician inside a measurement app.

Template: $templateTitle
Measurements:
$formattedResults

Explain in English what these measurements may clinically indicate. Keep it concise and practical. Do not diagnose. Do not recommend treatment. Mention that interpretation depends on patient age, symptoms, imaging quality, projection, and clinical context when relevant.
''';
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    }

    String message = 'Model list request failed (${response.statusCode}).';
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        message = error['message']?.toString() ?? message;
      } else if (error is String && error.isNotEmpty) {
        message = error;
      }
      final resetAt = decoded['resetAt']?.toString();
      if (resetAt != null && resetAt.isNotEmpty && !message.contains('reset')) {
        final parsed = DateTime.tryParse(resetAt);
        if (parsed != null) {
          message = '$message Resets on ${_formatDate(parsed.toLocal())}.';
        }
      }
    }
    throw AiSettingsException(message);
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class AiSettingsException implements Exception {
  const AiSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}
