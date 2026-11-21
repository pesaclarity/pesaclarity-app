import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/goals/savings_goal.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'savings_links.dart';

/// Savings goals: what the user is saving for and how far they have come.
abstract interface class GoalsRepository {
  /// Every goal, by priority and then oldest first. A goal saved in a
  /// savings pocket (see [setPocket]) reads what that pocket holds as its
  /// saved amount, and is achieved once that reaches the target.
  Future<List<SavingsGoal>> goals();

  Future<int> add({
    required String name,
    required int targetMinor,
    int savedMinor = 0,
    CalendarDate? targetDate,
  });

  /// Saves [goal]'s name, target, savings and date. Marks it achieved once
  /// the savings reach the target. For a goal saved in a savings pocket the
  /// amount the person typed before is kept as it was.
  Future<void> update(SavingsGoal goal);

  /// Keeps [goalId]'s money in the savings pocket [pocketId], so what is
  /// saved is what the pocket holds; with null, the goal goes back to the
  /// amount the person typed. A pocket backs one goal: any other goal
  /// saved in it lets go.
  ///
  /// Throws an [ArgumentError] for a goal or pocket that is not there, a
  /// pocket the person said is not theirs, and a pocket whose account
  /// counts in another currency than the goal.
  Future<void> setPocket(int goalId, int? pocketId);

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
    final backings = await _backings(rows);
    return [
      for (final row in rows)
        SavingsGoal(
          id: row.id,
          name: row.name,
          targetMinor: row.targetMinor,
          savedMinor: backings[row.id]?.savedMinor ?? row.savedMinor,
          targetDate: row.targetDate == null
              ? null
              : CalendarDate.local(row.targetDate!),
          currency: row.currency,
          // What a pocket holds changes without the goal being saved.
          status: backings[row.id] == null || row.status == GoalStatus.paused
              ? row.status
              : _statusFor(backings[row.id]!.savedMinor, row.targetMinor),
          backing: backings[row.id]?.backing,
        ),
    ];
  }

  /// The pocket each goal in [rows] is saved in and what it holds, by goal
  /// id. A pocket the person said is not theirs, and one in another
  /// currency than the goal, backs nothing: the goal reads what was typed.
  Future<Map<int, ({GoalBacking backing, int savedMinor})>> _backings(
    List<Goal> rows,
  ) async {
    final pocketIds = [for (final row in rows) ?row.savedInPocketId];
    if (pocketIds.isEmpty) return const {};
    final p = _db.savingsPockets;
    final a = _db.accounts;
    final found = {
      for (final row in await (_db.select(p).join([
        innerJoin(a, a.id.equalsExp(p.accountId)),
      ])..where(p.id.isIn(pocketIds))).get())
        row.readTable(p).id: (row.readTable(p), row.readTable(a)),
    };
    final held = <int, Map<int, int>>{};
    final out = <int, ({GoalBacking backing, int savedMinor})>{};
    for (final row in rows) {
      final (pocket, account) = found[row.savedInPocketId] ?? (null, null);
      if (pocket == null ||
          account == null ||
          pocket.ignored ||
          account.currency != row.currency) {
        continue;
      }
      final balances = held[account.id] ??= await savingsPocketBalances(
        _db,
        account.id,
      );
      final balance = balances[pocket.id] ?? 0;
      out[row.id] = (
        backing: GoalBacking(
          accountId: account.id,
          accountName: account.name,
          pocketId: pocket.id,
          pocketName: pocket.name,
          lockedUntil: pocket.lockedUntil == null
              ? null
              : CalendarDate.local(pocket.lockedUntil!),
        ),
        savedMinor: balance < 0 ? 0 : balance,
      );
    }
    return out;
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
          currency: Value(BaseCurrency.code),
          savedMinor: Value(savedMinor),
          targetDate: Value(targetDate?.startInstant),
          status: Value(_statusFor(savedMinor, targetMinor)),
        ),
      );

  @override
  Future<void> update(SavingsGoal goal) => _db.transaction(() async {
    final row = await (_db.select(
      _db.goals,
    )..where((g) => g.id.equals(goal.id))).getSingleOrNull();
    await (_db.update(_db.goals)..where((g) => g.id.equals(goal.id))).write(
      GoalsCompanion(
        name: Value(goal.name),
        targetMinor: Value(goal.targetMinor),
        // Saved in a pocket, the goal shows what the pocket holds: that is
        // not an amount the person typed.
        savedMinor: row?.savedInPocketId == null
            ? Value(goal.savedMinor)
            : const Value.absent(),
        targetDate: Value(goal.targetDate?.startInstant),
        status: Value(
          goal.status == GoalStatus.paused
              ? GoalStatus.paused
              : _statusFor(goal.savedMinor, goal.targetMinor),
        ),
      ),
    );
  });

  @override
  Future<void> setPocket(int goalId, int? pocketId) =>
      _db.transaction(() async {
        final goal = await (_db.select(
          _db.goals,
        )..where((g) => g.id.equals(goalId))).getSingleOrNull();
        if (goal == null) {
          throw ArgumentError.value(goalId, 'goalId', 'not found');
        }
        if (pocketId != null) {
          final pocket = await (_db.select(
            _db.savingsPockets,
          )..where((p) => p.id.equals(pocketId))).getSingleOrNull();
          final account = pocket == null
              ? null
              : await (_db.select(_db.accounts)
                      ..where((a) => a.id.equals(pocket.accountId)))
                    .getSingleOrNull();
          if (pocket == null || account == null || pocket.ignored) {
            throw ArgumentError.value(pocketId, 'pocketId', 'not a pocket');
          }
          if (account.currency != goal.currency) {
            throw ArgumentError.value(
              pocketId,
              'pocketId',
              'counts in ${account.currency}, the goal in ${goal.currency}',
            );
          }
          await (_db.update(_db.goals)..where(
                (g) =>
                    g.savedInPocketId.equals(pocketId) &
                    g.id.equals(goalId).not(),
              ))
              .write(const GoalsCompanion(savedInPocketId: Value(null)));
        }
        await (_db.update(_db.goals)..where((g) => g.id.equals(goalId))).write(
          GoalsCompanion(savedInPocketId: Value(pocketId)),
        );
      });

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
