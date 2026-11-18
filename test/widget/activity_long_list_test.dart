import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';
import '../perf/synthetic_ledger.dart';

/// Activity over months of history builds only the rows on screen, and
/// still scrolls through every day to "Show older".
void main() {
  testAppWidgets('a long Activity builds rows as they scroll in', (
    tester,
  ) async {
    final db = openTestDatabase();
    late SyntheticLedger ledger;
    await tester.runAsync(
      () async => ledger = await seedSyntheticLedger(db, count: 3000),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => ledger.end),
          loadedCategoriserProvider.overrideWithValue(
            const AsyncData(
              LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ActivityScreen()),
      ),
    );
    await settleFrames(tester);

    bool isRow(Widget w) => w.runtimeType.toString() == '_ActivityRow';
    final rows = find.byWidgetPredicate(isRow, skipOffstage: false);
    expect(rows, findsWidgets);
    // About 250 transactions in the first 60 days; a screenful is built.
    expect(rows.evaluate().length, lessThan(60));

    await tester.scrollUntilVisible(
      find.text('Show older'),
      2000,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 200,
    );
    expect(find.text('Show older'), findsOneWidget);
    expect(rows.evaluate().length, lessThan(60));
  });
}
