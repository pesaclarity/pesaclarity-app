import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/plan/month_plan.dart';
import '../../domain/plan/month_snapshot.dart';
import '../../domain/plan/plan_inputs.dart' as plan;
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// The monthly plan: recurring bills and budgets, one-offs and arrears, and
/// frozen month-end snapshots.
abstract interface class PlanRepository {
  Future<MonthPlan> monthPlan(YearMonth month);

  /// This month's budget for day-to-day categories, the pot behind
  /// safe-to-spend.
  Future<int> dayToDayBudgetMinor(YearMonth month);

  /// The latest month with a snapshot, or null when none is frozen.
  Future<YearMonth?> lastFrozenMonth();

  /// Stores [snapshot] and adds its arrears to the next month's plan.
  ///
  /// Returns false, changing nothing, when the month is already frozen, so
  /// arrears are never carried twice.
  Future<bool> saveSnapshot(MonthSnapshot snapshot);
}

class DriftPlanRepository implements PlanRepository {
  DriftPlanRepository(this._db);

  final AppDatabase _db;

  @override
  Future<MonthPlan> monthPlan(YearMonth month) async {
    final categories = await _db.select(_db.categories).get();
    final recurring =
        await (_db.select(_db.recurring)..where(
              (r) =>
                  r.startDate.isSmallerThanValue(month.endInstant) &
                  (r.endDate.isNull() |
                      r.endDate.isBiggerOrEqualValue(month.startInstant)),
            ))
            .get();
    final items = await (_db.select(
      _db.budgetItems,
    )..where((b) => b.month.equals(month.key))).get();

    return MonthPlan.build(
      month: month,
      categories: [
        for (final c in categories)
          plan.PlanCategory(
            id: c.id,
            type: c.type,
            isDailySpending: c.isDailySpending,
          ),
      ],
      recurring: [
        for (final r in recurring)
          plan.RecurringBill(
            id: r.id,
            name: r.name,
            categoryId: r.categoryId,
            amountMinor: r.amountMinor,
            frequency: r.frequency,
            startDate: CalendarDate.nairobi(r.startDate),
            endDate: r.endDate == null
                ? null
                : CalendarDate.nairobi(r.endDate!),
          ),
      ],
      items: [
        for (final b in items)
          plan.BudgetItem(
            id: b.id,
            month: YearMonth.fromKey(b.month),
            name: b.name,
            categoryId: b.categoryId,
            amountMinor: b.amountMinor,
            kind: b.kind,
            isPaid: b.isPaid,
          ),
      ],
    );
  }

  @override
  Future<int> dayToDayBudgetMinor(YearMonth month) async =>
      (await monthPlan(month)).dayToDayBudgetMinor;

  @override
  Future<YearMonth?> lastFrozenMonth() async {
    final latest = _db.budgetSnapshots.month.max();
    final row = await (_db.selectOnly(
      _db.budgetSnapshots,
    )..addColumns([latest])).getSingle();
    final key = row.read(latest);
    return key == null ? null : YearMonth.fromKey(key);
  }

  @override
  Future<bool> saveSnapshot(MonthSnapshot snapshot) =>
      _db.transaction(() async {
        final existing =
            await (_db.select(_db.budgetSnapshots)
                  ..where((s) => s.month.equals(snapshot.month.key))
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null) return false;

        for (final category in snapshot.categories) {
          await _db
              .into(_db.budgetSnapshots)
              .insert(
                BudgetSnapshotsCompanion.insert(
                  month: snapshot.month.key,
                  categoryId: Value(category.categoryId),
                  plannedMinor: category.plannedMinor,
                  actualMinor: category.actualMinor,
                  frozenAt: snapshot.frozenAt,
                ),
              );
        }
        for (final arrear in snapshot.carriedArrears) {
          await _db
              .into(_db.budgetItems)
              .insert(
                BudgetItemsCompanion.insert(
                  month: arrear.month.key,
                  name: arrear.name,
                  categoryId: Value(arrear.categoryId),
                  amountMinor: arrear.amountMinor,
                  kind: arrear.kind,
                ),
              );
        }
        return true;
      });
}

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => DriftPlanRepository(ref.watch(appDatabaseProvider)),
);
