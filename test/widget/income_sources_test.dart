import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';

import '../helpers/test_app.dart';

void main() {
  testAppWidgets('setup asks how money comes in, several at once', (
    tester,
  ) async {
    final db = openTestDatabase();
    await pumpApp(tester, db: db);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Continue with'));
    await tester.pumpAndSettle();

    expect(find.text('How does money usually come to you?'), findsOneWidget);
    await scrollTo(tester, find.text('Choose at least one to continue.'));
    await tester.scrollUntilVisible(
      find.byKey(const Key('income-support')),
      -200,
    );

    await tester.tap(find.byKey(const Key('income-support')));
    await scrollTo(tester, find.byKey(const Key('income-gigs')));
    await tester.tap(find.byKey(const Key('income-gigs')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Which accounts do you use?'), findsOneWidget);
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(IncomeSourcesController.settingsKey),
    );
    expect(saved, {
      'sources': ['gigs', 'support'],
    });
  });
}
