import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ortho_quant_md/services/ai_settings_service.dart';

const String surveyRecipient = 'ilker.eren@gmail.com';

const List<String> surveyFrequencyOptions = [
  'Daily',
  'Several times a week',
  'Weekly',
  'A few times a month',
  'Rarely',
];

/// Answers collected by the survey screen. `aiHelpfulness == 0` means the
/// user has not used the AI assistant.
class SurveyAnswers {
  final int satisfaction;
  final String frequency;
  final int aiHelpfulness;
  final String featureSuggestion;
  final String templateSuggestion;
  final String otherComments;
  final String contactEmail;

  const SurveyAnswers({
    required this.satisfaction,
    required this.frequency,
    required this.aiHelpfulness,
    this.featureSuggestion = '',
    this.templateSuggestion = '',
    this.otherComments = '',
    this.contactEmail = '',
  });

  String get _aiLabel =>
      aiHelpfulness == 0 ? "Haven't used" : '$aiHelpfulness/5';

  Map<String, dynamic> toJson() => {
    'satisfaction': satisfaction,
    'frequency': frequency,
    'aiHelpfulness': aiHelpfulness,
    'featureSuggestion': featureSuggestion.trim(),
    'templateSuggestion': templateSuggestion.trim(),
    'otherComments': otherComments.trim(),
    'contactEmail': contactEmail.trim(),
  };

  /// Subject used for the mail-app fallback; the server builds the same one.
  String subject(String appVersion, String platform) {
    final ai = aiHelpfulness == 0 ? 'AI n/a' : 'AI $aiHelpfulness/5';
    return '[OrthoQuant Survey] ★$satisfaction/5 · $ai · $platform $appVersion';
  }

  /// Body used for the mail-app fallback; the server builds the same one.
  String body({
    required String appVersion,
    required String platform,
    required String locale,
  }) {
    String section(String title, String text) =>
        '$title:\n${text.trim().isEmpty ? '-' : text.trim()}\n';

    return [
      'OrthoQuant MD – User Survey',
      '---------------------------',
      'Satisfaction: $satisfaction/5',
      'Usage frequency: $frequency',
      'AI helpfulness: $_aiLabel',
      '',
      section('Feature suggestion', featureSuggestion),
      section('Template suggestion', templateSuggestion),
      section('Other comments', otherComments),
      '---------------------------',
      'App $appVersion · $platform · $locale',
    ].join('\n');
  }
}

class SurveyException implements Exception {
  final String message;

  /// True when retrying via the mail app makes sense (network/server errors),
  /// false when the server deliberately refused (e.g. daily limit).
  final bool canFallback;

  const SurveyException(this.message, {this.canFallback = true});

  @override
  String toString() => message;
}

class SurveyService {
  // Public endpoint (not a secret); --dart-define can override it, e.g. to
  // point at the local functions emulator.
  static const String submitUrl = String.fromEnvironment(
    'ORTHOQUANT_SURVEY_URL',
    defaultValue:
        'https://europe-west1-orthoquantmd.cloudfunctions.net/submitSurvey',
  );
  static const Duration _timeout = Duration(seconds: 20);

  Future<void> submit(
    SurveyAnswers answers, {
    required String appVersion,
    required String platform,
    required String locale,
  }) async {
    final installationId = await AiSettingsService().getInstallationId();
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(submitUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              ...answers.toJson(),
              'installationId': installationId,
              'appVersion': appVersion,
              'platform': platform,
              'locale': locale,
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const SurveyException(
        "Couldn't reach the server. Check your connection.",
      );
    }

    if (response.statusCode == 200) return;

    String? message;
    try {
      message = (jsonDecode(response.body) as Map)['error']?.toString();
    } catch (_) {}
    throw SurveyException(
      message ?? 'Could not submit the survey.',
      // 400/429 are deliberate refusals; anything else is worth retrying.
      canFallback: response.statusCode != 400 && response.statusCode != 429,
    );
  }
}
