// Subcategories, with made-up records: a category's settings with its
// subcategories, the category picker opened on Transport, and Insights'
// breakdown of Transport by subcategory.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/features/insights/presentation/category_breakdown_screen.dart';
import 'package:pesaclarity/src/features/payees/presentation/categories_screen.dart';
import 'package:pesaclarity/src/features/payees/presentation/category_picker.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

final _now = eat(2026, 11, 26, 18);

/// Transport this month: Fuel, Uber, Matatu and some left as plain
/// Transport; and a little more on it in October. Returns Transport's id.
Future<int> _seed(AppDatabase db) async {
  final repo = DriftCategoriesRepository(db);
  final transport = (await repo.byKey('transport'))!.id;
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  Future<void> spend(
    int? category,
    List<int> shillings, {
    int month = 11,
  }) async {
    for (final (i, amount) in shillings.indexed) {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: eat(2026, month, 1 + i % 25, 8),
              amountMinor: kes(amount),
              direction: TransactionDirection.outflow,
              kind: const Value(TransactionKind.till),
              source: TransactionSource.manual,
              categoryOverrideId: Value(category),
            ),
          );
    }
  }

  for (final (name, amounts) in [
    ('Fuel', [3000, 2500, 2300, 2000]),
    ('Uber', [650, 520, 480, 450, 470, 430, 450]),
    ('Matatu', List.filled(22, 120)),
  ]) {
    await spend(
      await repo.create(
        name: name,
        type: CategoryType.expense,
        parentId: transport,
      ),
      amounts,
    );
  }
  await spend(transport, [300, 250, 200, 200, 180, 180]);
  await spend(transport, [9250, 9000], month: 10);
  return transport;
}

Widget _app(AppDatabase db, Widget home) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => _now),
  ],
  child: shotApp(home),
);

void main() {
  screenshot('subcategories-settings', (tester) async {
    final db = openTestDatabase();
    final transport = (await tester.runAsync(() => _seed(db)))!;
    await tester.pumpWidget(_app(db, CategoryScreen(categoryId: transport)));
    await snap(tester);
  });

  screenshot('subcategories-picker', (tester) async {
    final db = openTestDatabase();
    final transport = (await tester.runAsync(() => _seed(db)))!;
    await tester.pumpWidget(
      _app(
        db,
        Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Transaction')),
            body: Center(
              child: TextButton(
                onPressed: () => pickCategory(context, selectedId: transport),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await settleFrames(tester);
    await tester.tap(find.text('Open'));
    await snap(tester);
  });

  screenshot('subcategories-insights', (tester) async {
    final db = openTestDatabase();
    final transport = (await tester.runAsync(() => _seed(db)))!;
    await tester.pumpWidget(
      _app(db, CategoryBreakdownScreen(categoryId: transport)),
    );
    await snap(tester);
  });
}
