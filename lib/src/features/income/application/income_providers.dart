import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/budget/until_next_money.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/income/income_pattern.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/time/calendar.dart';

/// How money usually comes to the person, as they answered at setup.
class IncomeSourcesController extends AsyncNotifier<IncomeSources> {
  static const settingsKey = 'income.sources';

  @override
  Future<IncomeSources> build() async => IncomeSources.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> choose(Set<IncomeSource> picked) async {
    final sources = IncomeSources(picked);
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, sources.toJson());
    state = AsyncData(sources);
  }
}

final incomeSourcesProvider =
    AsyncNotifierProvider<IncomeSourcesController, IncomeSources>(
      IncomeSourcesController.new,
    );

/// The pattern of money arriving, learnt from the last [incomePatternDays].
final incomePatternProvider = FutureProvider<IncomePattern>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: today.addDays(-incomePatternDays).startInstant,
        to: today.addDays(1).startInstant,
      );
  return IncomePattern.of(entries, today: today);
});

/// How the plan finds the next money for these [sources] and [pattern].
NextMoneyBasis nextMoneyBasis(IncomeSources sources, IncomePattern pattern) {
  if (sources.irregular) return NextMoneyBasis.rolling;
  if (sources.noDate) return NextMoneyBasis.noDate;
  return pattern.steady ? NextMoneyBasis.rhythm : NextMoneyBasis.rolling;
}

/// Whether Home shows the monthly safe to spend: a salary alone (or no
/// answer yet) and a day-to-day budget in Plan.
bool monthlyPlanFits(IncomeSources sources, {required bool hasBudget}) =>
    hasBudget && (sources.salaryOnly || !sources.answered);

/// Safe to spend until the next money, from day-to-day accounts. Null
/// without any.
final untilNextMoneyProvider = FutureProvider<UntilNextMoney?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final accounts = (await ref.watch(accountsRepositoryProvider).openings())
      .where((a) => !a.isSavings)
      .toList();
  if (accounts.isEmpty) return null;
  final sources = await ref.watch(incomeSourcesProvider.future);
  final pattern = await ref.watch(incomePatternProvider.future);

  var opened = accounts.first.openingDate;
  for (final a in accounts) {
    if (a.openingDate.isBefore(opened)) opened = a.openingDate;
  }
  final windowStart = today.addDays(-paceWindowDays).startInstant;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: opened.isBefore(windowStart) ? opened : windowStart,
        to: today.addDays(1).startInstant,
      );
  final plan = await ref
      .watch(planRepositoryProvider)
      .monthPlan(today.yearMonth);
  final scheduledIds = scheduledCategoryIds(plan);

  final basis = nextMoneyBasis(sources, pattern);
  final next = pattern.nextExpected(today);
  final horizon = basis == NextMoneyBasis.rhythm && next != null
      ? next
      : today.addDays(rollingPlanDays);
  final bills = scheduledFlows(plan, entries, today: today)
      .where((f) => !f.isIncome && f.date.isBefore(horizon))
      .fold(0, (sum, f) => sum + f.amountMinor);
  final spentToday = entries
      .where((e) => e.date == today)
      .fold(0, (sum, e) => sum + paceSpendOf(e, scheduledIds));
  final pace = SpendingPace.fromHistory(
    entries,
    today: today,
    scheduledCategoryIds: scheduledIds,
    historyFrom: CalendarDate.local(opened),
  );

  return UntilNextMoney.calculate(
    today: today,
    basis: basis,
    onHandAtStartMinor: totalBalanceAt(
      accounts,
      entries,
      at: today.startInstant,
      where: (_) => true,
    ),
    billsMinor: bills,
    spentTodayMinor: spentToday,
    paceMinor: (pace.weekdayMinor * 5 + pace.weekendMinor * 2) ~/ 7,
    nextMoney: next,
  );
});
