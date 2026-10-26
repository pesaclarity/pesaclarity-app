import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// Wednesday 28 October 2026, 08:00 EAT.
DateTime _now() => DateTime.utc(2026, 10, 28, 5);

/// A Nairobi wall-clock time as UTC.
DateTime _eat(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour - 3, minute);

Future<void> _seed(AppDatabase db) async {
  Future<int> account(String name, AccountType type) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingDate: DateTime.utc(2026, 9),
        ),
      );
  Future<int> category(String key) async => (await (db.select(
    db.categories,
  )..where((c) => c.key.equals(key))).getSingle()).id;

  final mpesa = await account('M-Pesa', AccountType.mpesa);
  final bank = await account('I&M', AccountType.bank);

  Future<int> add(TransactionsCompanion t) =>
      db.into(db.transactions).insert(t);

  await add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: _eat(28, 7),
      amountMinor: 144000,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.till),
      source: TransactionSource.sms,
      counterpartyName: const Value('Naivas Juja City'),
      categoryOverrideId: Value(await category('groceries')),
    ),
  );
  final out = await add(
    TransactionsCompanion.insert(
      accountId: bank,
      occurredAt: _eat(28, 6),
      amountMinor: 200000,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.bank),
      source: TransactionSource.sms,
    ),
  );
  final into = await add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: _eat(28, 6, 2),
      amountMinor: 200000,
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.received),
      source: TransactionSource.sms,
      transferPairId: Value(out),
    ),
  );
  await (db.update(db.transactions)..where((t) => t.id.equals(out))).write(
    TransactionsCompanion(transferPairId: Value(into)),
  );
  await add(
    TransactionsCompanion.insert(
      accountId: bank,
      occurredAt: _eat(27, 9),
      amountMinor: 250000,
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.bank),
      source: TransactionSource.sms,
      counterpartyName: const Value('Employer Ltd'),
      categoryOverrideId: Value(await category('salary')),
    ),
  );
  await add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: _eat(27, 18),
      amountMinor: 35000,
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.sent),
      source: TransactionSource.sms,
      counterpartyKind: const Value(PayeeIdentifierKind.phone),
      counterpartyValue: const Value('0700***000'),
    ),
  );
}

Future<void> _pumpActivity(WidgetTester tester, AppDatabase db) async {
  // Tall enough that the whole feed is built.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(_now),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ActivityScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('Activity groups by day with weekly in and out', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pumpActivity(tester, db);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('Naivas Juja City'), findsOneWidget);
    expect(find.text('Groceries and household · M-Pesa'), findsOneWidget);
    expect(find.text('-1,440'), findsOneWidget);

    // The transfer shows once, as not spending.
    expect(find.text('I&M → M-Pesa'), findsOneWidget);
    expect(find.text('Own transfer · not spending'), findsOneWidget);

    // Weekly totals: groceries and the unnamed send out, salary in.
    expect(find.text('1,790'), findsOneWidget);
    expect(find.text('+2,500'), findsWidgets);

    expect(find.text('0700***000'), findsOneWidget);
    expect(find.text('Tap to name this payee'), findsOneWidget);
  });

  testAppWidgets('Activity filters by type, account and search', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pumpActivity(tester, db);

    await tester.tap(find.text('Spending only'));
    await tester.pumpAndSettle();
    expect(find.text('I&M → M-Pesa'), findsNothing);
    expect(find.text('Employer Ltd'), findsNothing);
    expect(find.text('Naivas Juja City'), findsOneWidget);

    await tester.tap(find.text('Spending only'));
    await tester.tap(find.text('I&M'));
    await tester.pumpAndSettle();
    expect(find.text('Naivas Juja City'), findsNothing);
    expect(find.text('Employer Ltd'), findsOneWidget);

    await tester.tap(find.text('All accounts'));
    await tester.enterText(find.byType(TextField), 'naivas');
    await tester.pumpAndSettle();
    expect(find.text('Naivas Juja City'), findsOneWidget);
    expect(find.text('Employer Ltd'), findsNothing);
  });

  testAppWidgets('naming an unknown number updates the feed', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pumpActivity(tester, db);

    await tester.tap(find.text('Tap to name this payee'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'John');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Tap to name this payee'), findsNothing);
    expect(find.text('John'), findsOneWidget);
  });

  testAppWidgets('+ adds a transaction that shows in Activity', (tester) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      overrides: [clockProvider.overrideWithValue(_now)],
    );
    await finishOnboarding(tester);

    await tester.tap(find.byTooltip('Add or import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a transaction'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount (KES)'),
      '250',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Paid to'), 'John');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Activity'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('John'), findsOneWidget);
    expect(find.text('-250'), findsOneWidget);
  });

  testAppWidgets('+ routes statement import to its screen', (tester) async {
    await pumpApp(tester, db: openTestDatabase());
    await finishOnboarding(tester);

    await tester.tap(find.byTooltip('Add or import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import a statement'));
    await tester.pumpAndSettle();
    expect(find.text('Bring in your history'), findsOneWidget);
  });

  testAppWidgets('Home numbers open Activity filtered', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await pumpApp(
      tester,
      db: db,
      overrides: [clockProvider.overrideWithValue(_now)],
    );
    await finishOnboarding(tester);

    expect(find.textContaining('At this pace'), findsOneWidget);
    await tapText(tester, 'Runway at this pace');

    expect(find.text('Search payee, amount, note'), findsOneWidget);
    expect(find.text('30 Sep – 28 Oct'), findsOneWidget);
    expect(find.text('Employer Ltd'), findsNothing);
    expect(find.text('Naivas Juja City'), findsOneWidget);
  });
}
