import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/plan/presentation/payday_screen.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// Thursday 26 November 2026, 09:00 EAT.
final now = DateTime.utc(2026, 11, 26, 6);

Future<int> categoryId(AppDatabase db, String key) async => (await (db.select(
  db.categories,
)..where((c) => c.key.equals(key))).getSingle()).id;

Future<void> addBill(
  AppDatabase db,
  String name,
  String key,
  int shillings, {
  required DateTime start,
}) async => db
    .into(db.recurring)
    .insert(
      RecurringCompanion.insert(
        name: name,
        categoryId: Value(await categoryId(db, key)),
        amountMinor: shillings * 100,
        frequency: RecurrenceFrequency.monthly,
        startDate: start,
      ),
    );

Future<void> spend(
  AppDatabase db,
  int account,
  String key,
  int shillings,
  DateTime at,
) async => db
    .into(db.transactions)
    .insert(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: at,
        amountMinor: shillings * 100,
        direction: TransactionDirection.outflow,
        kind: const Value(TransactionKind.till),
        categoryOverrideId: Value(await categoryId(db, key)),
        source: TransactionSource.sms,
      ),
    );

Future<void> seedNovember(AppDatabase db, {DateTime? start}) async {
  final from = start ?? DateTime.utc(2026, 11);
  await addBill(
    db,
    'Salary',
    'salary',
    181600,
    start: DateTime.utc(2026, 11, 25),
  );
  await addBill(
    db,
    'Rent',
    'rent',
    15000,
    start: from.add(const Duration(days: 4)),
  );
  await addBill(db, 'Eating out', 'eating_out', 5000, start: from);
  await addBill(db, 'Transport', 'transport', 12000, start: from);
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  await spend(db, account, 'rent', 15000, DateTime.utc(2026, 11, 5, 9));
  await spend(db, account, 'eating_out', 6420, DateTime.utc(2026, 11, 10, 9));
  await spend(db, account, 'transport', 6960, DateTime.utc(2026, 11, 12, 9));
}

Future<void> pumpScreen(
  WidgetTester tester,
  AppDatabase db,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('shows the plan against income, by category', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PlanScreen());

    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Planned of expected income'), findsOneWidget);
    expect(find.text('181,600'), findsWidgets);
    expect(find.text('32,000'), findsOneWidget);
    expect(find.text('Living 32,000'), findsOneWidget);

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Over'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('15,000 of 15,000'), findsOneWidget);
    expect(find.text('6,420 of 5,000'), findsOneWidget);

    expect(find.text('Surplus 149,600'), findsOneWidget);
    expect(find.text('All to savings'), findsOneWidget);

    // Salary was due yesterday, so payday autopilot is on offer.
    expect(find.text('Payday: split KES 181,600'), findsOneWidget);

    await tester.tap(find.text('Pending only'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
    expect(find.text('Show all'), findsOneWidget);
  });

  testAppWidgets('adds a one-off to the month', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PlanScreen());

    await tapText(tester, 'Add');
    await tester.tap(find.text('One-off'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Gift');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '2,500',
    );
    await tapText(tester, 'Save');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Gift'), findsOneWidget);
    expect(find.text('34,500'), findsOneWidget);
  });

  testAppWidgets('closes finished months and carries unpaid bills', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedNovember(db, start: DateTime.utc(2026, 10)),
    );
    await pumpScreen(tester, db, const PlanScreen());

    // October's rent was never paid, so it is carried into November.
    expect(find.textContaining('Carried forward'), findsOneWidget);
    expect(find.text('15,000 of 30,000'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.textContaining('This month is closed'), findsOneWidget);
  });

  testAppWidgets('payday checklist ticks off each task', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PaydayScreen());

    expect(find.text('KES 181,600'), findsOneWidget);
    expect(find.text('Set aside'), findsOneWidget);
    expect(find.text('Day-to-day spending'), findsOneWidget);
    expect(find.text('Surplus to savings'), findsOneWidget);
    expect(find.textContaining('0 of 2 done'), findsOneWidget);

    await tester.tap(find.text('Day-to-day spending'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of 2 done'), findsOneWidget);
  });
}
