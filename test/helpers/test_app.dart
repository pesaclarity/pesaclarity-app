import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';

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

/// Pumps the whole app on [db], as if launched fresh.
Future<void> pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  AppFlavor flavor = AppFlavor.foss,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appFlavorProvider.overrideWithValue(flavor),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const PesaClarityApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Goes from the welcome screen to Home, ticking M-Pesa on the way.
Future<void> finishOnboarding(WidgetTester tester) async {
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('M-Pesa'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan my messages'));
  await tester.pumpAndSettle();
}
