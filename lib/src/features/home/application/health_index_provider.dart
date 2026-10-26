import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/health/health_index.dart';
import '../../../domain/health/health_inputs.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/time/calendar.dart';

/// The index for the last full month, and its change on the month before.
class HealthOnHome {
  const HealthOnHome(this.index, this.change);

  final HealthIndex index;

  /// Null when the month before has no transactions to score.
  final int? change;
}

/// The Financial Health Index for the last full Nairobi month, or null when
/// that month has no transactions.
final healthIndexProvider = FutureProvider<HealthOnHome?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final month = today.yearMonth.previous;
  final before = month.previous;

  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  final plans = ref.watch(planRepositoryProvider);
  final monthPlan = await plans.monthPlan(month);
  final beforePlan = await plans.monthPlan(before);

  // A month's slack before the first scored month lets Fuliza repayments
  // find their draws; balances need everything since each account opened.
  var from = before.previous.startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: month.endInstant);

  HealthIndex? scoreOf(MonthPlan plan) {
    if (!entries.any((e) => plan.month.contains(e.date))) return null;
    return HealthIndex.compute(
      HealthInputs.forMonth(
        plan: plan,
        history: entries,
        savingsBalanceMinor: totalBalanceAt(
          accounts,
          entries,
          at: plan.month.endInstant,
          where: (a) => a.isSavings,
        ),
      ),
    );
  }

  final current = scoreOf(monthPlan);
  if (current == null) return null;
  return HealthOnHome(current, current.changeSince(scoreOf(beforePlan)));
});
