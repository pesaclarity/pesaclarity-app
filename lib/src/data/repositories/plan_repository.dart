import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// The monthly plan: recurring bills and budgets, one-offs and arrears.
abstract interface class PlanRepository {
  /// This month's budget for day-to-day categories, the pot behind
  /// safe-to-spend.
  Future<int> dayToDayBudgetMinor(YearMonth month);
}

class DriftPlanRepository implements PlanRepository {
  DriftPlanRepository(this._db);

  final AppDatabase _db;

  // TODO(plan): count weekly, quarterly and yearly lines once the monthly
  // plan builds occurrences per month.
  @override
  Future<int> dayToDayBudgetMinor(YearMonth month) async {
    final daily = _db.categories.isDailySpending.equals(true);

    final r = _db.recurring;
    final recurring =
        _db.select(r).join([
          innerJoin(_db.categories, _db.categories.id.equalsExp(r.categoryId)),
        ])..where(
          daily &
              r.frequency.equalsValue(RecurrenceFrequency.monthly) &
              r.startDate.isSmallerThanValue(month.endInstant) &
              (r.endDate.isNull() |
                  r.endDate.isBiggerOrEqualValue(month.startInstant)),
        );

    final b = _db.budgetItems;
    final items = _db.select(b).join([
      innerJoin(_db.categories, _db.categories.id.equalsExp(b.categoryId)),
    ])..where(daily & b.month.equals(month.key));

    var total = 0;
    for (final row in await recurring.get()) {
      total += row.readTable(r).amountMinor;
    }
    for (final row in await items.get()) {
      total += row.readTable(b).amountMinor;
    }
    return total;
  }
}

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => DriftPlanRepository(ref.watch(appDatabaseProvider)),
);
