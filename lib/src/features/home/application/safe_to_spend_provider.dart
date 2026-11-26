import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../../data/repositories/ledger_history.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/ledger/on_hand.dart';
import '../../../domain/time/calendar.dart';
import '../../goals/application/goals_aside_providers.dart';
import '../../income/application/income_providers.dart';
import '../../spaces/application/money_between_spaces_providers.dart';

/// Today's safe-to-spend, or null until there is a day-to-day budget.
final safeToSpendTodayProvider = FutureProvider<SafeToSpend?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final month = today.yearMonth;
  // Plan keeps monthly budgets; safe to spend follows the pay cycle when
  // there is a regular payday (as Home's since payday block), with the
  // month's budget prorated to it, and the calendar month otherwise.
  final monthly = await ref
      .watch(planRepositoryProvider)
      .dayToDayBudgetMinor(month);
  if (monthly <= 0) return null;
  final cycle = payCycleOf(
    await ref.watch(paydayProvider.future),
    today: today,
  );
  final first = cycle?.first ?? month.firstDay;
  final budget = cycle == null
      ? monthly
      : prorateMonthlyBudget(monthly, first: cycle.first, last: cycle.last);

  // Four weeks back for the weekend weight, or the whole period if longer.
  final historyStart = today.addDays(-28);
  final from = historyStart.isBefore(first) ? historyStart : first;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: from.startInstant,
        to: today.addDays(1).startInstant,
      );

  final goals = await ref.watch(goalsAsideProvider.future);
  return SafeToSpend.calculate(
    budgetMinor: budget,
    entries: entries,
    today: today,
    weekendWeightPercent: weekendWeightFromHistory(entries, today: today),
    // Below zero once Fuliza is counted: nothing is safe to spend.
    onHandMinor: await _onHand(ref, today, goalsKeptMinor: goals.totalMinor),
    goalsKeptMinor: goals.totalMinor,
    periodFirst: cycle?.first,
    periodLast: cycle?.last,
  );
});

/// Day-to-day money at the start of [today], Fuliza owed taken off, less
/// the rainy day fund and the goals kept aside; null without day-to-day
/// accounts.
Future<int?> _onHand(
  Ref ref,
  CalendarDate today, {
  required int goalsKeptMinor,
}) async {
  final accounts = [
    for (final a in await ref.read(accountsRepositoryProvider).openings())
      if (!a.isSavings) a,
  ];
  if (accounts.isEmpty) return null;
  var from = today.startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await readLedgerHistory(
    ref,
    from: from,
    to: today.addDays(1).startInstant,
  );
  final fund = await ref.read(rainyDayFundProvider.future);
  // What the accounts hold for another space is not the owner's to spend
  // (decision 0027, owner's decision 3).
  final notOwn = await notOwnMinorAt(ref, today.startInstant);
  return OnHand.at(
        accounts,
        entries,
        balances: await readJournal(ref),
        today: today,
        rainyDayMinor: fund.balanceMinor,
        goalsKeptMinor: goalsKeptMinor,
      ).totalMinor -
      notOwn;
}
