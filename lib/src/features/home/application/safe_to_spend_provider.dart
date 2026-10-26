import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/time/calendar.dart';

/// Today's safe-to-spend, or null until there is a day-to-day budget.
final safeToSpendTodayProvider = FutureProvider<SafeToSpend?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
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
  );
});
