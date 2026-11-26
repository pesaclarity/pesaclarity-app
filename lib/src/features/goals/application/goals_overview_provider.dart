import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/goals/debt_progress.dart';
import '../../../domain/goals/net_worth.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../balances/application/balances_providers.dart';
import '../../debts/application/debt_plan_provider.dart';
import '../../lending/application/lending_providers.dart';
import 'goals_aside_providers.dart';

/// Everything the Goals tab shows.
class GoalsOverview {
  const GoalsOverview({
    required this.today,
    required this.debts,
    required this.plan,
    required this.goals,
    required this.netWorth,
    required this.lending,
    this.fulizaShown = true,
  });

  final CalendarDate today;
  final DebtProgress debts;

  /// Null when nothing is owed.
  final PayoffComparison? plan;
  final List<SavingsGoal> goals;
  final NetWorth netWorth;
  final LendingOverview lending;

  /// Whether the space shows Fuliza (see `FulizaTracking`): until then it
  /// is not named among the examples of debts.
  final bool fulizaShown;
}

final goalsOverviewProvider = FutureProvider<GoalsOverview>((ref) async {
  // Balances set by hand, and every other change, show at once.
  ref.watch(ledgerChangesProvider);
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

  final untracked = await ref.watch(untrackedAccountIdsProvider.future);
  final accounts = [
    for (final a in await ref.watch(accountsRepositoryProvider).openings())
      if (!untracked.contains(a.id)) a,
  ];
  final journal = await readJournal(ref);

  final netWorth = NetWorth.at(
    now: now,
    accounts: accounts,
    balances: journal,
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
    fulizaShown: journal.fulizaShown,
  );
});

/// Reloads Goals, Lent and borrowed, and Debts after a change, and what
/// the goals kept aside take off On hand.
void refreshGoals(ProviderContainer container) {
  container
    ..invalidate(goalsAsideProvider)
    ..invalidate(debtPlanProvider)
    ..invalidate(lendingOverviewProvider)
    ..invalidate(goalsOverviewProvider);
}
