import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ortho_quant_md/services/survey_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final _emailController = TextEditingController();
  bool _submitting = false;

  bool _wantsReply = false;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _requiredAnswered =>
      _satisfaction != null && _frequency != null && _aiHelpfulness != null;

  bool get _emailValid => _emailPattern.hasMatch(_emailController.text.trim());

  bool get _canSubmit => _requiredAnswered && (!_wantsReply || _emailValid);

  @override
  void dispose() {
    _featureController.dispose();
    _templateController.dispose();
    _otherController.dispose();
    _emailController.dispose();
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
    if (!mounted) return;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final platform = _platformLabel();

    final answers = SurveyAnswers(
      satisfaction: _satisfaction!,
      frequency: _frequency!,
      aiHelpfulness: _aiHelpfulness!,
      featureSuggestion: _featureController.text,
      templateSuggestion: _templateController.text,
      otherComments: _otherController.text,
      contactEmail: _wantsReply ? _emailController.text : '',
    );

    try {
      await SurveyService().submit(
        answers,
        appVersion: appVersion,
        platform: platform,
        locale: locale,
      );
      if (mounted) Navigator.pop(context, true);
    } on SurveyException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (e.canFallback) {
        await _showSendFailedDialog(
          e.message,
          subject: answers.subject(appVersion, platform.split(' ').first),
          body: answers.body(
            appVersion: appVersion,
            platform: platform,
            locale: locale,
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Offered when the server can't be reached: send via the mail app, or
  /// copy the answers if no mail app can be opened.
  Future<void> _showSendFailedDialog(
    String message, {
    required String subject,
    required String body,
  }) async {
    final useMail = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Couldn't send survey",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '$message\n\nYou can send your answers with your mail app instead.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('USE MAIL APP'),
          ),
        ],
      ),
    );
    if (useMail != true || !mounted) return;

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
    if (launched) {
      Navigator.pop(context, false);
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: 'To: $surveyRecipient\nSubject: $subject\n\n$body'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No mail app found. Your answers were copied — paste them into '
          'an email to $surveyRecipient.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF111820),
      appBar: AppBar(
        title: const Text('Quick Survey'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/home_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                'Help us improve OrthoQuant MD. It takes less than a minute.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
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
                          title: Text(
                            option,
                            style: const TextStyle(color: Colors.white),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: _accent,
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? _accent
                                : Colors.white54,
                          ),
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
                    _Pill(
                      label: "I haven't used it",
                      selected: _aiHelpfulness == 0,
                      onTap: () => setState(() => _aiHelpfulness = 0),
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
              _QuestionCard(
                number: 7,
                title: 'Would you like a reply?',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Pill(
                          label: 'No',
                          selected: !_wantsReply,
                          onTap: () => setState(() => _wantsReply = false),
                        ),
                        const SizedBox(width: 10),
                        _Pill(
                          label: 'Yes',
                          selected: _wantsReply,
                          onTap: () => setState(() => _wantsReply = true),
                        ),
                      ],
                    ),
                    if (_wantsReply) ...[
                      const SizedBox(height: 14),
                      _FreeText(
                        controller: _emailController,
                        hint: 'Your email address',
                        singleLine: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
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
                !_requiredAnswered
                    ? 'Please answer questions 1–3 to submit.'
                    : _wantsReply && !_emailValid
                    ? 'Please enter a valid email so we can reply.'
                    : _wantsReply
                    ? "We'll reply to your email."
                    : 'Your answers are sent anonymously.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
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
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (optional)
                  const TextSpan(
                    text: '  (optional)',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
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
                      color: value == i ? accent : Colors.white38,
                    ),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: value == i ? Colors.white : Colors.white70,
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
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            Text(
              highLabel,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
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
  final bool singleLine;
  final ValueChanged<String>? onChanged;

  const _FreeText({
    required this.controller,
    this.hint,
    this.singleLine = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      onChanged: onChanged,
      minLines: singleLine ? 1 : 2,
      maxLines: singleLine ? 1 : 5,
      maxLength: singleLine ? null : 1000,
      keyboardType: singleLine ? TextInputType.emailAddress : null,
      autocorrect: !singleLine,
      textCapitalization: singleLine
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF00BFA5),
      decoration: InputDecoration(
        hintText: hint ?? 'Type here…',
        hintStyle: const TextStyle(color: Colors.white38),
        counterStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00BFA5)),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00BFA5);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? accent : Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: selected ? accent : Colors.white38),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
