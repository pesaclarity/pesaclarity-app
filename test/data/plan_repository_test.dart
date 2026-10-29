import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/plan_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/month_snapshot.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/plan/application/month_close.dart';

void main() {
  late AppDatabase db;
  late DriftPlanRepository plan;
  late DriftTransactionsRepository transactions;
  late int rent;
  late int food;
  late int account;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    plan = DriftPlanRepository(db);
    transactions = DriftTransactionsRepository(db);
    rent = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(name: 'Rent', type: CategoryType.expense),
        );
    food = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: 'Food',
            type: CategoryType.expense,
            isDailySpending: const Value(true),
          ),
        );
    account = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026),
          ),
        );
    await db
        .into(db.recurring)
        .insert(
          RecurringCompanion.insert(
            name: 'Rent',
            categoryId: Value(rent),
            amountMinor: 2500000,
            frequency: RecurrenceFrequency.monthly,
            // 01:00 EAT on 5 September.
            startDate: DateTime.utc(2026, 9, 4, 22),
          ),
        );
    await db
        .into(db.recurring)
        .insert(
          RecurringCompanion.insert(
            name: 'Food',
            categoryId: Value(food),
            amountMinor: 300000,
            frequency: RecurrenceFrequency.weekly,
            startDate: DateTime.utc(2026, 10),
          ),
        );
  });
  
  tearDown(() => db.close());

  Future<void> spend(int categoryId, DateTime at, int amount) =>
      transactions.add(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: at,
          amountMinor: amount,
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.paybill),
          categoryOverrideId: Value(categoryId),
          source: TransactionSource.sms,
        ),
      );

  test('builds a month from recurring lines in Nairobi dates', () async {
    final october = await plan.monthPlan(YearMonth(2026, 10));
    final rentLine = october.lines.singleWhere((l) => l.categoryId == rent);
    expect(rentLine.dueDate, CalendarDate(2026, 10, 5));
    // Five Thursdays in October 2026.
    expect(await plan.dayToDayBudgetMinor(YearMonth(2026, 10)), 1500000);
    expect(await plan.dayToDayBudgetMinor(YearMonth(2026, 9)), 0);
  });

  test('closes finished months in order and carries arrears once', () async {
    await spend(rent, DateTime.utc(2026, 10, 5, 7), 2500000);
    await spend(food, DateTime.utc(2026, 10, 9, 7), 200000);

    final now = DateTime.utc(2026, 11, 2, 6);
    final closed = await closeFinishedMonths(
      plan: plan,
      transactions: transactions,
      firstMonth: YearMonth(2026, 9),
      now: now,
    );
    expect(closed, [YearMonth(2026, 9), YearMonth(2026, 10)]);
    expect(await plan.lastFrozenMonth(), YearMonth(2026, 10));

    // September's unpaid rent was carried into October and paid first there,
    // which leaves October's own rent unpaid and carried into November.
    final november = await plan.monthPlan(YearMonth(2026, 11));
    final arrears = november.lines
        .where((l) => l.source == PlanLineSource.arrears)
        .toList();
    expect(arrears.map((l) => (l.categoryId, l.amountMinor)), [
      (rent, 2500000),
    ]);

    final snapshots = await (db.select(
      db.budgetSnapshots,
    )..where((s) => s.month.equals(202610))).get();
    final byCategory = {
      for (final s in snapshots) s.categoryId: (s.plannedMinor, s.actualMinor),
    };
    expect(byCategory[rent], (5000000, 2500000));
    expect(byCategory[food], (1500000, 200000));

    final again = await closeFinishedMonths(
      plan: plan,
      transactions: transactions,
      firstMonth: YearMonth(2026, 9),
      now: now,
    );
    expect(again, isEmpty);
    final items = await db.select(db.budgetItems).get();
    expect(items, hasLength(2));
  });

  test('refuses to store the same month twice', () async {
    final september = YearMonth(2026, 9);
    final snapshot = MonthSnapshot.freeze(
      MonthReview.of(await plan.monthPlan(september), const []),
      now: DateTime.utc(2026, 10, 2),
    );
    expect(await plan.saveSnapshot(snapshot), isTrue);
    expect(await plan.saveSnapshot(snapshot), isFalse);
    expect(await db.select(db.budgetItems).get(), hasLength(1));
    expect(await plan.lastFrozenMonth(), september);
  });
}
