import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/plan/month_plan.dart';
import '../../domain/plan/month_snapshot.dart';
import '../../domain/plan/plan_inputs.dart' as plan;
import '../../domain/plan/surplus_split.dart';
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

  /// [month]'s frozen results, or null while it is open.
  Future<MonthSnapshot?> snapshot(YearMonth month);

  /// The earliest month any bill, budget or one-off belongs to, where month
  /// closing starts. Null for an empty plan.
  Future<YearMonth?> firstPlanMonth();

  Future<plan.RecurringBill?> recurringBill(int id);

  /// Adds a recurring bill, or updates the one with [id]. Returns its id.
  Future<int> saveRecurring({
    int? id,
    required String name,
    required int? categoryId,
    required int amountMinor,
    required RecurrenceFrequency frequency,
    required CalendarDate startDate,
    CalendarDate? endDate,
  });

  /// Removes a recurring bill from [from] onwards. Earlier months keep it;
  /// a bill that starts in or after [from] is deleted outright.
  Future<void> stopRecurring(int id, {required YearMonth from});

  /// Adds a one-off or arrear, or updates the one with the item's id.
  /// Returns its id.
  Future<int> saveBudgetItem(plan.BudgetItem item);

  Future<void> deleteBudgetItem(int id);

  /// The share of a surplus that goes to debt, in basis points.
  Future<int> surplusDebtShareBasisPoints();

  Future<void> setSurplusDebtShareBasisPoints(int basisPoints);
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
            key: c.key,
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
      items: [for (final b in items) _budgetItem(b)],
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

  @override
  Future<MonthSnapshot?> snapshot(YearMonth month) async {
    final rows = await (_db.select(
      _db.budgetSnapshots,
    )..where((s) => s.month.equals(month.key))).get();
    if (rows.isEmpty) return null;
    final arrears =
        await (_db.select(_db.budgetItems)..where(
              (b) =>
                  b.month.equals(month.next.key) &
                  b.kind.equalsValue(BudgetItemKind.carriedArrears),
            ))
            .get();
    return MonthSnapshot(
      month: month,
      frozenAt: rows.first.frozenAt,
      categories: [
        for (final r in rows)
          CategorySnapshot(
            categoryId: r.categoryId,
            plannedMinor: r.plannedMinor,
            actualMinor: r.actualMinor,
          ),
      ],
      carriedArrears: [for (final b in arrears) _budgetItem(b)],
    );
  }

  @override
  Future<YearMonth?> firstPlanMonth() async {
    final firstStart = _db.recurring.startDate.min();
    final startRow = await (_db.selectOnly(
      _db.recurring,
    )..addColumns([firstStart])).getSingle();
    final firstItem = _db.budgetItems.month.min();
    final itemRow = await (_db.selectOnly(
      _db.budgetItems,
    )..addColumns([firstItem])).getSingle();

    final start = startRow.read(firstStart);
    final itemKey = itemRow.read(firstItem);
    final months = [
      if (start != null) YearMonth.nairobi(start),
      if (itemKey != null) YearMonth.fromKey(itemKey),
    ];
    if (months.isEmpty) return null;
    return months.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  }

  @override
  Future<plan.RecurringBill?> recurringBill(int id) async {
    final row = await (_db.select(
      _db.recurring,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return plan.RecurringBill(
      id: row.id,
      name: row.name,
      categoryId: row.categoryId,
      amountMinor: row.amountMinor,
      frequency: row.frequency,
      startDate: CalendarDate.nairobi(row.startDate),
      endDate: row.endDate == null ? null : CalendarDate.nairobi(row.endDate!),
    );
  }

  @override
  Future<int> saveRecurring({
    int? id,
    required String name,
    required int? categoryId,
    required int amountMinor,
    required RecurrenceFrequency frequency,
    required CalendarDate startDate,
    CalendarDate? endDate,
  }) async {
    final row = RecurringCompanion(
      name: Value(name),
      categoryId: Value(categoryId),
      amountMinor: Value(amountMinor),
      frequency: Value(frequency),
      startDate: Value(startDate.startInstant),
      endDate: Value(endDate?.startInstant),
    );
    if (id == null) return _db.into(_db.recurring).insert(row);
    await (_db.update(_db.recurring)..where((r) => r.id.equals(id))).write(row);
    return id;
  }

  @override
  Future<void> stopRecurring(int id, {required YearMonth from}) async {
    final bill = await recurringBill(id);
    if (bill == null) return;
    if (bill.startDate.yearMonth.compareTo(from) >= 0) {
      await (_db.delete(_db.recurring)..where((r) => r.id.equals(id))).go();
      return;
    }
    final lastDay = from.previous.lastDay;
    final end = bill.endDate;
    if (end != null && end.isBefore(lastDay)) return;
    await (_db.update(_db.recurring)..where((r) => r.id.equals(id))).write(
      RecurringCompanion(endDate: Value(lastDay.startInstant)),
    );
  }

  @override
  Future<int> saveBudgetItem(plan.BudgetItem item) async {
    final row = BudgetItemsCompanion(
      month: Value(item.month.key),
      name: Value(item.name),
      categoryId: Value(item.categoryId),
      amountMinor: Value(item.amountMinor),
      kind: Value(item.kind),
      isPaid: Value(item.isPaid),
    );
    final id = item.id;
    if (id == null) return _db.into(_db.budgetItems).insert(row);
    await (_db.update(
      _db.budgetItems,
    )..where((b) => b.id.equals(id))).write(row);
    return id;
  }

  @override
  Future<void> deleteBudgetItem(int id) =>
      (_db.delete(_db.budgetItems)..where((b) => b.id.equals(id))).go();

  static const surplusShareKey = 'plan.surplus_debt_share_bp';

  @override
  Future<int> surplusDebtShareBasisPoints() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(surplusShareKey))).getSingleOrNull();
    final value = int.tryParse(row?.value ?? '');
    if (value == null || value < 0 || value > 10000) {
      return defaultDebtShareBasisPoints;
    }
    return value;
  }

  @override
  Future<void> setSurplusDebtShareBasisPoints(int basisPoints) {
    if (basisPoints < 0 || basisPoints > 10000) {
      throw ArgumentError.value(basisPoints, 'basisPoints');
    }
    return _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: surplusShareKey,
            value: '$basisPoints',
          ),
        );
  }
}

plan.BudgetItem _budgetItem(BudgetItem b) => plan.BudgetItem(
  id: b.id,
  month: YearMonth.fromKey(b.month),
  name: b.name,
  categoryId: b.categoryId,
  amountMinor: b.amountMinor,
  kind: b.kind,
  isPaid: b.isPaid,
);

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => DriftPlanRepository(ref.watch(appDatabaseProvider)),
);
