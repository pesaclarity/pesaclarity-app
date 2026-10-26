import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/goals/savings_goal.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Savings goals: what the user is saving for and how far they have come.
abstract interface class GoalsRepository {
  /// Every goal, by priority and then oldest first.
  Future<List<SavingsGoal>> goals();

  Future<int> add({
    required String name,
    required int targetMinor,
    int savedMinor = 0,
    CalendarDate? targetDate,
  });

  /// Saves [goal]'s name, target, savings and date. Marks it achieved once
  /// the savings reach the target.
  Future<void> update(SavingsGoal goal);

  Future<void> remove(int goalId);
}

class DriftGoalsRepository implements GoalsRepository {
  DriftGoalsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<SavingsGoal>> goals() async {
    final rows =
        await (_db.select(_db.goals)..orderBy([
              (g) => OrderingTerm.desc(g.priority),
              (g) => OrderingTerm.asc(g.id),
            ]))
            .get();
    return [
      for (final row in rows)
        SavingsGoal(
          id: row.id,
          name: row.name,
          targetMinor: row.targetMinor,
          savedMinor: row.savedMinor,
          targetDate: row.targetDate == null
              ? null
              : CalendarDate.nairobi(row.targetDate!),
          currency: row.currency,
          status: row.status,
        ),
    ];
  }

  @override
  Future<int> add({
    required String name,
    required int targetMinor,
    int savedMinor = 0,
    CalendarDate? targetDate,
  }) => _db
      .into(_db.goals)
      .insert(
        GoalsCompanion.insert(
          name: name,
          targetMinor: targetMinor,
          savedMinor: Value(savedMinor),
          targetDate: Value(targetDate?.startInstant),
          status: Value(_statusFor(savedMinor, targetMinor)),
        ),
      );

  @override
  Future<void> update(SavingsGoal goal) =>
      (_db.update(_db.goals)..where((g) => g.id.equals(goal.id))).write(
        GoalsCompanion(
          name: Value(goal.name),
          targetMinor: Value(goal.targetMinor),
          savedMinor: Value(goal.savedMinor),
          targetDate: Value(goal.targetDate?.startInstant),
          status: Value(
            goal.status == GoalStatus.paused
                ? GoalStatus.paused
                : _statusFor(goal.savedMinor, goal.targetMinor),
          ),
        ),
      );

  @override
  Future<void> remove(int goalId) => _db.transaction(() async {
    await (_db.update(_db.transactions)..where((t) => t.goalId.equals(goalId)))
        .write(const TransactionsCompanion(goalId: Value(null)));
    await (_db.delete(_db.goals)..where((g) => g.id.equals(goalId))).go();
  });
}

GoalStatus _statusFor(int saved, int target) =>
    saved >= target ? GoalStatus.achieved : GoalStatus.active;

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => DriftGoalsRepository(ref.watch(appDatabaseProvider)),
);
