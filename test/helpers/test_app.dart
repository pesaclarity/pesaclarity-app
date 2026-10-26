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
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';

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
/// inbox by default) in place of the phone's messages, plus any [overrides].
Future<void> pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  AppFlavor flavor = AppFlavor.foss,
  SmsSource? sms,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appFlavorProvider.overrideWithValue(flavor),
        appDatabaseProvider.overrideWithValue(db),
        smsSourceProvider.overrideWithValue(sms ?? FakeSmsSource()),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
        ...overrides,
      ],
      child: const PesaClarityApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [text] into view, then taps it.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
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
