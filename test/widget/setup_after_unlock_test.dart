import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';

import '../helpers/test_app.dart';

/// Like the phone: the database opens on first use and fails while app lock
/// still holds the key, and Drift keeps that failure for the session.
AppDatabase _lockedUntilReleased(ReleasedDatabaseKey key) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(
    LazyDatabase(() async {
      if (key.value == null) {
        throw StateError('The database is locked; unlock the app first');
      }
      return NativeDatabase.memory();
    }),
  );
  addTearDown(db.close);
  return db;
}

void main() {
  late Directory models;

  setUp(() {
    models = Directory.systemTemp.createTempSync('models');
    addTearDown(() => models.deleteSync(recursive: true));
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  for (final pick in ['KES', 'USD']) {
    testAppWidgets('setup continues after picking $pick on a database that '
        'opens only after unlock', (tester) async {
      final key = ReleasedDatabaseKey();
      final db = _lockedUntilReleased(key);
      await pumpApp(
        tester,
        db: db,
        overrides: [
          releasedDatabaseKeyProvider.overrideWithValue(key),
          // A real folder, as on the phone, so learning reaches its reads.
          modelFolderProvider.overrideWith((ref) async => models),
        ],
      );

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      if (pick != 'KES') {
        await tester.enterText(find.byKey(const Key('currency-search')), pick);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('currency-$pick')));
        await tester.pumpAndSettle();
      }
      final button = find.widgetWithText(FilledButton, 'Continue with $pick');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('How does money usually come to you?'), findsOneWidget);

      await pickSalaryIncome(tester);
      expect(find.text('Which accounts do you use?'), findsOneWidget);
    });
  }
}
