import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// Wednesday 28 October 2026, 08:00 EAT.
DateTime _now() => DateTime.utc(2026, 10, 28, 5);

Future<void> _seed(AppDatabase db) async {
  final mpesa = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026, 9),
        ),
      );
  Future<void> till(String name, String till, int hour, int amount) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: DateTime.utc(2026, 10, 28, hour - 3),
          amountMinor: amount,
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.till),
          source: TransactionSource.sms,
          counterpartyName: Value(name),
          counterpartyKind: const Value(PayeeIdentifierKind.till),
          counterpartyValue: Value(till),
        ),
      );
  await till('Naivas Juja City', '000123', 7, 144000);
  await till('John Duka', '000456', 6, 30000);
  await till('John Duka', '000456', 5, 20000);
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(_now),
        loadedCategoriserProvider.overrideWithValue(
          const AsyncData(
            LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ActivityScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

void main() {
  testAppWidgets('one tap accepts a suggested category', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pump(tester, db);

    expect(find.text('Groceries and household? 60%'), findsOneWidget);
    await tester.tap(find.byTooltip('Accept Groceries and household'));
    await _settle(tester);

    expect(find.text('Groceries and household · M-Pesa'), findsOneWidget);
    final log = await tester.runAsync(
      () => db.select(db.categoryConfirmations).get(),
    );
    expect(log!.single.accepted, isTrue);
  });

  testAppWidgets('a chosen category wins for that payee from then on', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pump(tester, db);

    expect(find.text('Uncategorised · Tap to choose'), findsNWidgets(2));
    await tester.tap(find.text('Uncategorised · Tap to choose').first);
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);
    await tester.tap(find.text('Eating out'));
    await _settle(tester);

    expect(find.text('Eating out · M-Pesa'), findsOneWidget);
    expect(find.text('Eating out? 100%'), findsOneWidget);

    // The sheet shows the suggestion with its source; Change picks another.
    await tester.tap(find.text('Eating out? 100%'));
    await tester.pumpAndSettle();
    expect(find.text('SUGGESTED CATEGORY'), findsOneWidget);
    expect(
      find.text('100% sure · Your earlier choice for this payee'),
      findsOneWidget,
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries and household'));
    await _settle(tester);

    expect(find.text('Groceries and household · M-Pesa'), findsOneWidget);
    expect(find.text('Eating out · M-Pesa'), findsOneWidget);
  });
}
