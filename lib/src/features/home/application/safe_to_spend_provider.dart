import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/ledger/on_hand.dart';
import '../../../domain/time/calendar.dart';
import '../../income/application/income_providers.dart';

/// Today's safe-to-spend, or null until there is a day-to-day budget.
final safeToSpendTodayProvider = FutureProvider<SafeToSpend?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final month = today.yearMonth;
  final budget = await ref
      .watch(planRepositoryProvider)
      .dayToDayBudgetMinor(month);
  if (budget <= 0) return null;

  // Four weeks back for the weekend weight, or the whole month if longer.
  final historyStart = today.addDays(-28);
  final from = historyStart.isBefore(month.firstDay)
      ? historyStart
      : month.firstDay;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: from.startInstant,
        to: today.addDays(1).startInstant,
      );

  return SafeToSpend.calculate(
    budgetMinor: budget,
    entries: entries,
    today: today,
    weekendWeightPercent: weekendWeightFromHistory(entries, today: today),
    // Below zero once Fuliza is counted: nothing is safe to spend.
    onHandMinor: await _onHand(ref, today),
  );
});

/// Day-to-day money at the start of [today], Fuliza owed taken off, less
/// the rainy day fund; null without day-to-day accounts.
Future<int?> _onHand(Ref ref, CalendarDate today) async {
  final accounts = [
    for (final a in await ref.read(accountsRepositoryProvider).openings())
      if (!a.isSavings) a,
  ];
  if (accounts.isEmpty) return null;
  var from = today.startInstant;
  for (final a in accounts) {
    if (a.openingDate.isBefore(from)) from = a.openingDate;
  }
  final entries = await ref
      .read(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: today.addDays(1).startInstant);
  final fund = await ref.read(rainyDayFundProvider.future);
  return OnHand.at(
    accounts,
    entries,
    today: today,
    rainyDayMinor: fund.balanceMinor,
  ).totalMinor;
}
