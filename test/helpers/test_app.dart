import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/google_id_token_source.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';
import 'package:pesaclarity/src/features/reminders/data/reminder_notifications.dart';
import 'package:pesaclarity/src/features/security/data/biometric_authenticator.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';

import 'fake_app_lock.dart';
import 'fake_auth.dart';
import 'fake_reminders.dart';
import 'fake_sms_source.dart';

/// Like [testWidgets], but unmounts the app at the end so Drift's stream
/// queries close inside the fake clock instead of leaving a timer pending.
void testAppWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

/// A fresh in-memory database, closed when the test ends.
AppDatabase openTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// Pumps the whole app on [db], as if launched fresh, with [sms] (an empty
/// inbox by default) in place of the phone's messages, fakes for
/// notifications and email unless given, and any [overrides]. Without [auth]
/// the build behaves as one with no server configured.
///
/// App lock reads its settings from [secureStore] (empty, so no lock, by
/// default) and uses [biometrics] in place of the fingerprint prompt.
Future<void> pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  AppFlavor flavor = AppFlavor.foss,
  SmsSource? sms,
  AuthApi? auth,
  SessionStore? sessions,
  GoogleIdTokenSource? google,
  ReminderNotifications? notifications,
  PolicyMailer? mailer,
  SecureStore? secureStore,
  BiometricAuthenticator? biometrics,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...appLockOverrides(store: secureStore, biometrics: biometrics),
        appFlavorProvider.overrideWithValue(flavor),
        appDatabaseProvider.overrideWithValue(db),
        smsSourceProvider.overrideWithValue(sms ?? FakeSmsSource()),
        authApiProvider.overrideWithValue(auth ?? const UnconfiguredAuthApi()),
        sessionStoreProvider.overrideWithValue(
          sessions ?? InMemorySessionStore(),
        ),
        deviceNameSourceProvider.overrideWithValue(
          const FakeDeviceNameSource(),
        ),
        if (google != null)
          googleIdTokenSourceProvider.overrideWithValue(google),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
        statementReadBatchProvider.overrideWithValue(
          (pages) async => readStatement(pages),
        ),
        reminderNotificationsProvider.overrideWithValue(
          notifications ?? FakeReminderNotifications(),
        ),
        policyMailerProvider.overrideWithValue(mailer ?? FakePolicyMailer()),
        privacyPolicyProvider.overrideWithValue(AsyncData(bundledPolicy())),
        ...overrides,
      ],
      child: const PesaClarityApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [text] into view, then taps it.
Future<void> tapText(WidgetTester tester, String text) async {
  await scrollTo(tester, find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Goes from the welcome screen to Home, ticking M-Pesa and allowing SMS
/// access on the way.
Future<void> finishOnboarding(WidgetTester tester) async {
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('M-Pesa'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan my messages'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Allow access to messages');
  await tapText(tester, 'Continue');
}

/// Scrolls the screen's list until [finder] is built and on screen, even
/// when the list has not built it yet.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// The bundled privacy policy, read straight from disk, since asset loading
/// does not finish inside a widget test's fake clock.
PrivacyPolicy bundledPolicy() => PrivacyPolicy.fromAssets(
  metadata: jsonDecode(
    File('assets/policy/privacy_policy.json').readAsStringSync(),
  ) as Map<String, Object?>,
  markdown: File('assets/policy/privacy_policy.md').readAsStringSync(),
);
