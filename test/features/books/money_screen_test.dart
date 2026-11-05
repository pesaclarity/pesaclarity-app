import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/books/presentation/money_screen.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

Future<void> _seed(AppDatabase db) async {
  Future<int> account(String name, AccountType type, int opening) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingDate: eat(2026, 11, 1, 0),
          openingBalanceMinor: Value(opening),
        ),
      );
  final sales = await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(name: 'Sale', type: CategoryType.income),
      );
  final transport = (await (db.select(
    db.categories,
  )..where((c) => c.name.equals('Transport'))).getSingle()).id;
  final cash = await account('Cash', AccountType.cash, kes(1200));
  final mpesa = await account('M-Pesa', AccountType.mpesa, kes(10000));
  await account('Equity', AccountType.bank, kes(40000));

  Future<int> add(TransactionsCompanion t) =>
      db.into(db.transactions).insert(t);
  await add(
    TransactionsCompanion.insert(
      accountId: cash,
      occurredAt: eat(2026, 11, 5, 14, 40),
      amountMinor: kes(350),
      direction: TransactionDirection.inflow,
      source: TransactionSource.manual,
      categoryOverrideId: Value(sales),
    ),
  );
  await add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: eat(2026, 11, 5, 13, 15),
      amountMinor: kes(1150),
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.received),
      source: TransactionSource.sms,
      counterpartyName: const Value('Grace W.'),
      categoryOverrideId: Value(sales),
    ),
  );
  await add(
    TransactionsCompanion.insert(
      accountId: cash,
      occurredAt: eat(2026, 11, 4, 8, 10),
      amountMinor: kes(250),
      direction: TransactionDirection.outflow,
      source: TransactionSource.manual,
      categoryOverrideId: Value(transport),
    ),
  );
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => eat(2026, 11, 5, 18)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const MoneyScreen()),
    ),
  );
  await settleFrames(tester);
}

void main() {
  testAppWidgets('Money shows each column, then the days in and out', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pump(tester, db);

    expect(find.text('Money in and out'), findsOneWidget);
    expect(find.byKey(const Key('money-balance-cash')), findsOneWidget);
    expect(find.text('1,300'), findsOneWidget);
    expect(find.text('11,150'), findsOneWidget);
    expect(find.text('40,000'), findsOneWidget);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('In 1,500 · Out 0'), findsOneWidget);
    expect(find.text('Sale'), findsOneWidget);
    expect(find.text('Sale · Grace W.'), findsOneWidget);
    expect(find.text('+1,150'), findsOneWidget);

    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('In 0 · Out 250'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('-250'), findsOneWidget);
  });

  testAppWidgets('Money hides amounts while balances are hidden', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pump(tester, db);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MoneyScreen)),
    );
    container.read(balancesHiddenProvider.notifier).set(true);
    await settleFrames(tester);

    expect(find.text('40,000'), findsNothing);
    expect(find.text('+1,150'), findsNothing);
    expect(find.text(maskedDigits), findsNWidgets(3));
  });

  test('a business gets its own tabs in the same bar', () {
    expect(tabsFor(SpaceKind.personal).map((t) => t.label), [
      'Home',
      'Activity',
      'Plan',
      'Goals',
      'Insights',
    ]);
    expect(tabsFor(SpaceKind.household), personalTabs);
    expect(tabsFor(SpaceKind.business).map((t) => t.label), [
      'Today',
      'Money',
      'People',
      'Insights',
    ]);
    expect(tabsFor(SpaceKind.business, services: true).map((t) => t.label), [
      'Today',
      'Money',
      'Clients',
      'Insights',
    ]);
  });

  test('the full Activity list shows as Money in a business', () {
    expect(selectedTabOf(businessTabs, ShellBranch.money), 1);
    expect(selectedTabOf(businessTabs, ShellBranch.activity), 1);
    expect(selectedTabOf(businessTabs, ShellBranch.plan), -1);
    expect(selectedTabOf(personalTabs, ShellBranch.activity), 1);
    expect(selectedTabOf(personalTabs, ShellBranch.money), -1);
    // Lent and borrowed sits under Goals; a business finds it in People.
    expect(selectedTabOf(businessTabs, ShellBranch.goals), 2);
  });

  testWidgets('the bar shows no tab as current when none fits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PillNavigationBar(
            destinations: businessTabs,
            selectedIndex: -1,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home), findsNothing);
  });
}
