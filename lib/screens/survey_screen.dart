import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const String surveyRecipient = 'ilker.eren@gmail.com';

const List<String> surveyFrequencyOptions = [
  'Daily',
  'Several times a week',
  'Weekly',
  'A few times a month',
  'Rarely',
];

/// Answers collected by [SurveyScreen]. `aiHelpfulness == 0` means the user
/// has not used the AI assistant.
class SurveyAnswers {
  final int satisfaction;
  final String frequency;
  final int aiHelpfulness;
  final String featureSuggestion;
  final String templateSuggestion;
  final String otherComments;

  const SurveyAnswers({
    required this.satisfaction,
    required this.frequency,
    required this.aiHelpfulness,
    this.featureSuggestion = '',
    this.templateSuggestion = '',
    this.otherComments = '',
  });

  String get _aiLabel => aiHelpfulness == 0 ? "Haven't used" : '$aiHelpfulness/5';

  String subject(String appVersion, String platform) {
    final ai = aiHelpfulness == 0 ? 'AI n/a' : 'AI $aiHelpfulness/5';
    return '[OrthoQuant Survey] ★$satisfaction/5 · $ai · $platform $appVersion';
  }

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

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  static const Color _accent = Color(0xFF00BFA5);

  int? _satisfaction;
  String? _frequency;
  int? _aiHelpfulness;
  final _featureController = TextEditingController();
  final _templateController = TextEditingController();
  final _otherController = TextEditingController();
  bool _submitting = false;

  bool get _canSubmit =>
      _satisfaction != null && _frequency != null && _aiHelpfulness != null;

  @override
  void dispose() {
    _featureController.dispose();
    _templateController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    if (Platform.isIOS) return 'iOS ${Platform.operatingSystemVersion}';
    if (Platform.isMacOS) return 'macOS ${Platform.operatingSystemVersion}';
    if (Platform.isAndroid) return 'Android';
    return Platform.operatingSystem;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);

    final info = await PackageInfo.fromPlatform();
    final appVersion = '${info.version}+${info.buildNumber}';
    final platformShort = kIsWeb
        ? 'Web'
        : Platform.isIOS
        ? 'iOS'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isAndroid
        ? 'Android'
        : Platform.operatingSystem;
    if (!mounted) return;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final answers = SurveyAnswers(
      satisfaction: _satisfaction!,
      frequency: _frequency!,
      aiHelpfulness: _aiHelpfulness!,
      featureSuggestion: _featureController.text,
      templateSuggestion: _templateController.text,
      otherComments: _otherController.text,
    );
    final subject = answers.subject(appVersion, platformShort);
    final body = answers.body(
      appVersion: appVersion,
      platform: _platformLabel(),
      locale: locale,
    );

    final uri = Uri(
      scheme: 'mailto',
      path: surveyRecipient,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (e) {
      debugPrint('Error launching survey email: $e');
    }
    if (!mounted) return;
    setState(() => _submitting = false);

    if (launched) {
      Navigator.pop(context, true);
    } else {
      await _showNoMailAppDialog(subject, body);
    }
  }

  Future<void> _showNoMailAppDialog(String subject, String body) async {
    final copied = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No mail app found'),
        content: const Text(
          "We couldn't open a mail app on this device. Copy your answers "
          'and send them to $surveyRecipient from any email account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: 'To: $surveyRecipient\nSubject: $subject\n\n$body',
                ),
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('COPY ANSWERS'),
          ),
        ],
      ),
    );
    if (copied == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Answers copied. Paste them into an email to $surveyRecipient.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Survey')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Help us improve OrthoQuant MD. It takes less than a minute.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _QuestionCard(
              number: 1,
              title: 'How satisfied are you with OrthoQuant MD?',
              child: _LikertScale(
                value: _satisfaction,
                lowLabel: 'Very dissatisfied',
                highLabel: 'Very satisfied',
                onChanged: (v) => setState(() => _satisfaction = v),
              ),
            ),
            _QuestionCard(
              number: 2,
              title: 'How often do you use the app?',
              child: RadioGroup<String>(
                groupValue: _frequency,
                onChanged: (v) => setState(() => _frequency = v),
                child: Column(
                  children: [
                    for (final option in surveyFrequencyOptions)
                      RadioListTile<String>(
                        value: option,
                        title: Text(option),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: _accent,
                      ),
                  ],
                ),
              ),
            ),
            _QuestionCard(
              number: 3,
              title: 'How much does the AI assistant make your work easier?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LikertScale(
                    value: (_aiHelpfulness ?? 0) > 0 ? _aiHelpfulness : null,
                    lowLabel: 'Not at all',
                    highLabel: 'A great deal',
                    onChanged: (v) => setState(() => _aiHelpfulness = v),
                  ),
                  const SizedBox(height: 8),
                  ChoiceChip(
                    label: const Text("I haven't used it"),
                    selected: _aiHelpfulness == 0,
                    selectedColor: _accent.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _aiHelpfulness = 0),
                  ),
                ],
              ),
            ),
            _QuestionCard(
              number: 4,
              title: 'Would you like to suggest a new feature?',
              optional: true,
              child: _FreeText(controller: _featureController),
            ),
            _QuestionCard(
              number: 5,
              title: 'Would you like to suggest a new template?',
              optional: true,
              child: _FreeText(
                controller: _templateController,
                hint: 'Name, reference, landmarks…',
              ),
            ),
            _QuestionCard(
              number: 6,
              title: 'Anything else you would like to add?',
              optional: true,
              child: _FreeText(controller: _otherController),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _canSubmit && !_submitting ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'SUBMIT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              _canSubmit
                  ? 'Your mail app will open with your answers ready to send.'
                  : 'Please answer questions 1–3 to submit.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int number;
  final String title;
  final bool optional;
  final Widget child;

  const _QuestionCard({
    required this.number,
    required this.title,
    required this.child,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$number. $title',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (optional)
                  const TextSpan(
                    text: '  (optional)',
                    style: TextStyle(color: Colors.black38, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LikertScale extends StatelessWidget {
  final int? value;
  final String lowLabel;
  final String highLabel;
  final ValueChanged<int> onChanged;

  const _LikertScale({
    required this.value,
    required this.lowLabel,
    required this.highLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00BFA5);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(i),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value == i ? accent : Colors.transparent,
                    border: Border.all(
                      color: value == i ? accent : Colors.black26,
                    ),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: value == i ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              lowLabel,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            Text(
              highLabel,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ],
    );
  }
}

class _FreeText extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;

  const _FreeText({required this.controller, this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 5,
      maxLength: 1000,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint ?? 'Type here…',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00BFA5)),
        ),
      ),
    );
  }
}
