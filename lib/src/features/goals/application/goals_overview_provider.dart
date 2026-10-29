import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/goals/debt_progress.dart';
import '../../../domain/goals/net_worth.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../debts/application/debt_plan_provider.dart';
import '../../lending/application/lending_providers.dart';

/// Everything the Goals tab shows.
class GoalsOverview {
  const GoalsOverview({
    required this.today,
    required this.debts,
    required this.plan,
    required this.goals,
    required this.netWorth,
    required this.lending,
  });

  final CalendarDate today;
  final DebtProgress debts;

  /// Null when nothing is owed.
  final PayoffComparison? plan;
  final List<SavingsGoal> goals;
  final NetWorth netWorth;
  final LendingOverview lending;
}

final goalsOverviewProvider = FutureProvider<GoalsOverview>((ref) async {
  final now = ref.watch(clockProvider)();
  final today = CalendarDate.local(now);
  final month = today.yearMonth;
  final debtsRepository = ref.watch(debtsRepositoryProvider);
  final plan = await ref.watch(debtPlanProvider.future);
  final lending = await ref.watch(lendingOverviewProvider.future);

  final debts = await debtsRepository.debts(today: today);
  final progress = DebtProgress.of(
    debts,
    await debtsRepository.startingBalances(),
  );

  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  var from = month.startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: now);

  final netWorth = NetWorth.at(
    now: now,
    accounts: accounts,
    entries: entries,
    debtsOwedMinor: progress.remainingMinor,
    debtsRepaidThisMonthMinor: await debtsRepository.repaidBetween(
      month.startInstant,
      now,
    ),
    lentOutstandingMinor: lending.owedToYouMinor,
    lentOutstandingAtMonthStartMinor: lending.lent.fold(
      0,
      (sum, l) => sum + l.outstandingAt(month.firstDay),
    ),
  );

  return GoalsOverview(
    today: today,
    debts: progress,
    plan: plan,
    goals: await ref.watch(goalsRepositoryProvider).goals(),
    netWorth: netWorth,
    lending: lending,
  );
});

/// Reloads Goals, Lent and borrowed, and Debts after a change.
void refreshGoals(ProviderContainer container) {
  container
    ..invalidate(debtPlanProvider)
    ..invalidate(lendingOverviewProvider)
    ..invalidate(goalsOverviewProvider);
}
