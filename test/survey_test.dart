import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ortho_quant_md/screens/survey_screen.dart';
import 'package:ortho_quant_md/services/survey_service.dart';

void main() {
  group('SurveyAnswers', () {
    test('subject summarises scores, platform and version', () {
      const answers = SurveyAnswers(
        satisfaction: 4,
        frequency: 'Weekly',
        aiHelpfulness: 5,
      );
      expect(
        answers.subject('0.7.1+6', 'iOS'),
        '[OrthoQuant Survey] ★4/5 · AI 5/5 · iOS 0.7.1+6',
      );
    });

    test("'haven't used' AI and empty free text are rendered clearly", () {
      const answers = SurveyAnswers(
        satisfaction: 3,
        frequency: 'Rarely',
        aiHelpfulness: 0,
        templateSuggestion: '  Tibial slope  ',
      );
      expect(answers.subject('1.0.0+1', 'macOS'), contains('AI n/a'));

      final body = answers.body(
        appVersion: '1.0.0+1',
        platform: 'macOS 15',
        locale: 'en-US',
      );
      expect(body, contains("AI helpfulness: Haven't used"));
      expect(body, contains('Usage frequency: Rarely'));
      expect(body, contains('Feature suggestion:\n-\n'));
      expect(body, contains('Template suggestion:\nTibial slope\n'));
      expect(body, endsWith('App 1.0.0+1 · macOS 15 · en-US'));
    });
  });

  test('toJson trims free text and keeps the optional email', () {
    const answers = SurveyAnswers(
      satisfaction: 5,
      frequency: 'Daily',
      aiHelpfulness: 0,
      otherComments: '  great app ',
      contactEmail: ' doc@example.com ',
    );
    expect(answers.toJson(), {
      'satisfaction': 5,
      'frequency': 'Daily',
      'aiHelpfulness': 0,
      'featureSuggestion': '',
      'templateSuggestion': '',
      'otherComments': 'great app',
      'contactEmail': 'doc@example.com',
    });
  });

  testWidgets(
    'submit requires questions 1–3 and a valid email when a reply is wanted',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: SurveyScreen()));

      FilledButton submit() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'SUBMIT'),
      );
      expect(submit().onPressed, isNull);

      await tester.tap(find.text('4').first);
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect(submit().onPressed, isNull);

      await tester.tap(find.text("I haven't used it"));
      await tester.pump();
      expect(submit().onPressed, isNotNull);

      // Asking for a reply requires a valid email before submitting.
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'not-an-email');
      await tester.pump();
      expect(submit().onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'doc@example.com');
      await tester.pump();
      expect(submit().onPressed, isNotNull);

      await tester.tap(find.text('No'));
      await tester.pump();
      expect(find.text('Your email address'), findsNothing);
      expect(submit().onPressed, isNotNull);
    },
  );
}
