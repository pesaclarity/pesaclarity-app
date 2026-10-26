import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/plan/month_snapshot.dart';
import '../../../domain/time/calendar.dart';

/// Freezes every month that has ended since the last snapshot, oldest first,
/// so each month's arrears reach the next month's plan before it is frozen.
///
/// [firstMonth] is where history starts, used when nothing is frozen yet.
/// Returns the months frozen.
Future<List<YearMonth>> closeFinishedMonths({
  required PlanRepository plan,
  required TransactionsRepository transactions,
  required YearMonth firstMonth,
  required DateTime now,
}) async {
  final months = monthsToFreeze(
    firstMonth: firstMonth,
    lastFrozen: await plan.lastFrozenMonth(),
    now: now,
  );
  for (final month in months) {
    final entries = await transactions.ledgerEntries(
      from: month.startInstant,
      to: month.endInstant,
    );
    final review = MonthReview.of(await plan.monthPlan(month), entries);
    await plan.saveSnapshot(MonthSnapshot.freeze(review, now: now));
  }
  return months;
}
