// Budget alerts and the bills calendar, for the accessibility check
// (tool/accessibility.sh): Plan with a budget alert card, a category's own
// "Warn me at", Plan's bills as a calendar with a day's list, and the
// Budget alerts settings in Profile, each at every text size, in light and
// dark. Not marketing screenshots, so tool/screenshots.sh skips them.
// Made-up names, amounts and dates.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/features/reminders/presentation/reminders_settings_card.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Sunday 22 November 2026, 09:41 in Nairobi.
final _now = eat(2026, 11, 22, 9, 41);

Future<int> _category(AppDatabase db, String key) async => (await (db.select(
  db.categories,
)..where((c) => c.key.equals(key))).getSingle()).id;

/// Food at 80% of its plan, a few bills through the month, some paid.
Future<void> _seed(AppDatabase db) async {
  Future<void> bill(String name, String key, int shillings, int day) async => db
      .into(db.recurring)
      .insert(
        RecurringCompanion.insert(
          name: name,
          categoryId: Value(await _category(db, key)),
          amountMinor: kes(shillings),
          frequency: RecurrenceFrequency.monthly,
          startDate: eat(2026, 11, day, 9),
        ),
      );
  await bill('Salary', 'salary', 110000, 30);
  await bill('Food', 'groceries', 10000, 1);
  await bill('Transport', 'transport', 6000, 1);
  await bill('Rent', 'rent', 25000, 1);
  await bill('Water bill', 'utilities', 1200, 18);
  await bill('School fees', 'school_fees', 15000, 25);
  await bill('Car insurance', 'health', 4500, 30);

  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  Future<void> spend(String key, int shillings, int day) async => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: eat(2026, 11, day, 10),
          amountMinor: kes(shillings),
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.till),
          categoryOverrideId: Value(await _category(db, key)),
          source: TransactionSource.sms,
        ),
      );
  await spend('groceries', 8000, 12);
  await spend('transport', 3100, 14);
  await spend('rent', 25000, 1);
}

Widget _app(AppDatabase db, Widget home) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    personalDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => _now),
    deviceRegionProvider.overrideWithValue('KE'),
    activeSpaceProvider.overrideWithValue(Space.personal),
    ...appLockOverrides(),
  ],
  child: shotApp(home),
);

Future<void> _settle(WidgetTester tester) async {
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

void main() {
  if (!checkAccessibility) return;

  screenshot('plan-budget-alert', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(_app(db, const PlanScreen()));
    await _settle(tester);
    await snap(tester);

    await tester.tap(find.textContaining('Groceries and household:').first);
    await _settle(tester);
    await snap(tester, variant: 'category-sheet');
  });

  screenshot('plan-bills-calendar', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(_app(db, const PlanScreen()));
    await _settle(tester);
    final calendar = find.byKey(const Key('plan-bills-calendar'));
    await tester.scrollUntilVisible(calendar, 300);
    await _settle(tester);
    await tester.tap(calendar);
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('bills-calendar')),
      300,
    );
    await _settle(tester);
    await snap(tester);
  });

  screenshot('profile-budget-alerts', (tester) async {
    final db = openTestDatabase();
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: RemindersSettingsCard(),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    await snap(tester);
  });
}
