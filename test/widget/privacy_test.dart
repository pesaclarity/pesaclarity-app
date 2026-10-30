import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';

import '../helpers/fake_reminders.dart';
import '../helpers/test_app.dart';

void main() {
  Future<void> openPrivacy(WidgetTester tester) async {
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Privacy');
  }

  CheckboxListTile choice(WidgetTester tester, String title) =>
      tester.widget(find.widgetWithText(CheckboxListTile, title));

  testAppWidgets('shows the promises, choices and policy version', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase());
    await openPrivacy(tester);

    expect(find.text('IN PLAIN WORDS'), findsOneWidget);
    expect(
      find.text('Your transactions, payees and debts stay on this phone.'),
      findsOneWidget,
    );
    expect(choice(tester, 'Help improve the app').value, isTrue);
    expect(choice(tester, 'Contribute to licensed models').value, isFalse);
    expect(choice(tester, 'Send crash reports').value, isFalse);
    await scrollTo(tester, find.text('Version 1.4 · updated 30 Oct 2026'));
    expect(find.text('Version 1.4 · updated 30 Oct 2026'), findsOneWidget);
  });

  testAppWidgets('saves a choice with the policy version and time', (
    tester,
  ) async {
    final db = openTestDatabase();
    await pumpApp(tester, db: db);
    await openPrivacy(tester);

    await tapText(tester, 'Contribute to licensed models');
    expect(choice(tester, 'Contribute to licensed models').value, isTrue);

    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db).readJson(ConsentController.recordKey),
    );
    final licensed =
        (saved!['choices']! as Map)['licensedModels'] as Map<String, Object?>;
    expect(licensed['value'], isTrue);
    expect(licensed['policyVersion'], '1.4');
    expect(DateTime.tryParse(licensed['changedAt']! as String), isNotNull);
  });

  testAppWidgets('emails a copy of the full policy', (tester) async {
    final mailer = FakePolicyMailer();
    await pumpApp(tester, db: openTestDatabase(), mailer: mailer);
    await openPrivacy(tester);

    await tapText(tester, 'Email me a copy');
    final draft = mailer.drafts.single;
    expect(draft.subject, 'Pesa Clarity privacy policy, version 1.4');
    expect(draft.body, startsWith('Privacy policy\nVersion 1.4'));
    expect(draft.body, contains('WHAT STAYS ON YOUR PHONE'));
  });

  testAppWidgets('says how to send a copy without an email app', (
    tester,
  ) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      mailer: FakePolicyMailer(opens: false),
    );
    await openPrivacy(tester);

    await tapText(tester, 'Email me a copy');
    expect(
      find.text('Set up an email app on this phone to send a copy.'),
      findsOneWidget,
    );
  });

  testAppWidgets('opens the full policy', (tester) async {
    await pumpApp(tester, db: openTestDatabase());
    await openPrivacy(tester);

    await tapText(tester, 'Read the full privacy policy');
    expect(find.text('Privacy policy'), findsWidgets);
    expect(find.text('The short version'), findsOneWidget);
    await scrollTo(tester, find.text('What our server holds'));
    expect(find.text('What our server holds'), findsOneWidget);
  });

  testAppWidgets('asks again when the policy is newer than the one agreed', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: ConsentController.recordKey,
              value:
                  '{"acceptedVersion": "0.9", '
                  '"acceptedAt": "2026-09-01T09:00:00.000Z", "choices": {}}',
            ),
          ),
    );
    await pumpApp(tester, db: db);
    await finishOnboarding(tester);

    expect(find.text('Our privacy policy changed'), findsOneWidget);
    expect(find.text('The first version of the policy.'), findsOneWidget);

    await tapText(tester, 'Send crash reports');
    await tapText(tester, 'Agree and continue');
    expect(find.text('Our privacy policy changed'), findsNothing);
    expect(find.text('Safe to spend today'), findsOneWidget);

    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db).readJson(ConsentController.recordKey),
    );
    expect(saved!['acceptedVersion'], '1.4');
    final crash =
        (saved['choices']! as Map)['crashReports'] as Map<String, Object?>;
    expect(crash['value'], isTrue);
    expect(crash['policyVersion'], '1.4');
  });
}
