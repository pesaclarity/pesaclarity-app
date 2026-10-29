import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/activity/presentation/add_transaction_sheet.dart';
import 'package:pesaclarity/src/features/payees/presentation/category_picker.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_item_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

Category _category(int id, String name, {bool daily = false}) => Category(
  id: id,
  name: name,
  type: CategoryType.expense,
  isDailySpending: daily,
);

void main() {
  group('mostUsedCategories', () {
    final all = [
      _category(1, 'Rent'),
      _category(2, 'Groceries', daily: true),
      _category(3, 'Fuel'),
      _category(4, 'Snacks', daily: true),
      _category(5, 'Health'),
      _category(6, 'Tax'),
      _category(7, 'Giving'),
    ];

    test('the most used first, ties in list order', () {
      final top = mostUsedCategories(all, {3: 9, 5: 2, 1: 2}, count: 3);
      expect(top.map((c) => c.id), [3, 1, 5]);
    });

    test('without use, day-to-day categories come first', () {
      final top = mostUsedCategories(all, const {}, count: 3);
      expect(top.map((c) => c.id), [2, 4, 1]);
    });

    test('the chosen category is always shown', () {
      final top = mostUsedCategories(all, const {}, count: 2, selectedId: 7);
      expect(top.map((c) => c.id), [7, 2, 4]);
    });
  });

  late AppDatabase db;
  setUp(() => db = openTestDatabase());

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testAppWidgets('the category field shows the five most used, then all', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final account = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026),
            ),
          );
      final fuel = await (db.select(
        db.categories,
      )..where((c) => c.key.equals('fuel'))).getSingle();
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                accountId: account,
                occurredAt: eat(2026, 10, 1 + i),
                amountMinor: kes(100),
                direction: TransactionDirection.outflow,
                source: TransactionSource.manual,
                categoryOverrideId: Value(fuel.id),
              ),
            );
      }
    });
    await pump(tester, const AddTransactionSheet());

    expect(find.text('Choose later'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-transaction-category')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);
    expect(find.text('MOST USED'), findsOneWidget);
    // Money out lists no income categories.
    expect(find.text('Salary'), findsNothing);
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Tax'), findsNothing);

    final sheet = find
        .descendant(
          of: find.byType(CategoryPicker),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('category-show-all')),
      200,
      scrollable: sheet,
    );
    await tester.tap(find.byKey(const Key('category-show-all')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tax'), 200, scrollable: sheet);
    await tester.tap(find.text('Tax'));
    await tester.pumpAndSettle();
    expect(find.text('Tax'), findsOneWidget);
    expect(find.text('Choose a category'), findsNothing);
  });

  testAppWidgets('how often is a short list, shown in full', (tester) async {
    await pump(tester, PlanItemForm(month: YearMonth(2026, 11)));

    expect(find.text('Every month'), findsOneWidget);
    await tester.tap(find.text('Every month'));
    await tester.pumpAndSettle();
    expect(find.text('Every week'), findsOneWidget);
    expect(find.text('Every year'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2)); // no search box
    await tester.tap(find.text('Every year'));
    await tester.pumpAndSettle();
    expect(find.text('Every year'), findsOneWidget);
    expect(find.text('Every week'), findsNothing);
  });
}
