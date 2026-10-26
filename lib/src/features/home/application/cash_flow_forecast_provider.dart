import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/time/calendar.dart';

/// This month's cash-flow forecast for day-to-day accounts (everything but
/// SACCO and money market accounts), or null when there are none.
final cashFlowForecastProvider = FutureProvider<CashFlowForecast?>((ref) async {
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final accounts = (await ref.watch(accountsRepositoryProvider).openings())
      .where((a) => !a.isSavings)
      .toList();
  if (accounts.isEmpty) return null;

  var opened = accounts.first.openingDate;
  for (final a in accounts) {
    if (a.openingDate.isBefore(opened)) opened = a.openingDate;
  }
  final windowStart = today.addDays(-paceWindowDays).startInstant;
  final tomorrow = today.addDays(1).startInstant;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: opened.isBefore(windowStart) ? opened : windowStart,
        to: tomorrow,
      );

  return CashFlowForecast.project(
    balanceMinor: totalBalanceAt(
      accounts,
      entries,
      at: tomorrow,
      where: (_) => true,
    ),
    today: today,
    plan: await ref.watch(planRepositoryProvider).monthPlan(today.yearMonth),
    entries: entries,
    historyFrom: CalendarDate.nairobi(opened),
  );
});
