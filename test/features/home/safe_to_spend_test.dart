import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  group('safeToSpendTodayProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Monday 26 October 2026, 08:00 EAT.
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> category(String name, {required bool daily}) => db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: name,
            type: CategoryType.expense,
            isDailySpending: Value(daily),
          ),
        );

    test('is null without a day-to-day budget', () async {
      expect(await container.read(safeToSpendTodayProvider.future), isNull);
    });

    test('uses monthly budgets and this month\'s one-offs', () async {
      final food = await category('Food', daily: true);
      final rent = await category('Rent', daily: false);
      final account = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026),
            ),
          );

      Future<void> recurring(int categoryId, int amount, {DateTime? end}) => db
          .into(db.recurring)
          .insert(
            RecurringCompanion.insert(
              name: 'Line $amount',
              categoryId: Value(categoryId),
              amountMinor: amount,
              frequency: RecurrenceFrequency.monthly,
              startDate: DateTime.utc(2026),
              endDate: Value(end),
            ),
          );
      await recurring(food, 2500000);
      await recurring(rent, 4000000);
      await recurring(food, 999900, end: DateTime.utc(2026, 9, 30));
      await db
          .into(db.budgetItems)
          .insert(
            BudgetItemsCompanion.insert(
              month: 202610,
              name: 'Visitors',
              categoryId: Value(food),
              amountMinor: 500000,
              kind: BudgetItemKind.oneOff,
            ),
          );

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: DateTime.utc(2026, 10, 10, 9),
              amountMinor: 2400000,
              direction: TransactionDirection.outflow,
              categoryOverrideId: Value(food),
              source: TransactionSource.manual,
            ),
          );

      final result = await container.read(safeToSpendTodayProvider.future);
      expect(result, isNotNull);
      expect(result!.today, CalendarDate(2026, 10, 26));
      expect(result.budgetMinor, 3000000);
      expect(result.spentBeforeTodayMinor, 2400000);
      expect(result.weekdayLimitMinor, 100000);
    });
  });

  testWidgets('Home shows what is safe to spend today', (tester) async {
    final result = SafeToSpend(
      today: CalendarDate(2026, 10, 26),
      budgetMinor: 3000000,
      spentBeforeTodayMinor: 2400000,
      spentTodayMinor: 40000,
      weekdaysLeft: 5,
      weekendDaysLeft: 1,
      weekdayLimitMinor: 100000,
      weekendLimitMinor: 100000,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          safeToSpendTodayProvider.overrideWith((ref) async => result),
          healthIndexProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KES 600'), findsOneWidget);
    expect(
      find.text('Weekdays KES 1,000, weekends KES 1,000.'),
      findsOneWidget,
    );
  });
}
