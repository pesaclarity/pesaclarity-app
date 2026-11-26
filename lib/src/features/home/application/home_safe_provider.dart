import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/budget/until_next_money.dart';
import '../../../domain/income/income_sources.dart';
import '../../income/application/income_providers.dart';
import 'cash_flow_forecast_provider.dart';
import 'safe_to_spend_provider.dart';

/// Which safe to spend Home shows: the month's plan for a salary alone
/// ([monthly]), or what is on hand spread until the next money
/// ([untilNext]) for everyone else. Both null until there is one.
class HomeSafe {
  const HomeSafe({this.monthly, this.untilNext});

  final SafeToSpend? monthly;
  final UntilNextMoney? untilNext;

  /// Today's money is spent, the plan is used up or a payment may not go
  /// through: the support card never asks then.
  bool tight({bool failingCharges = false}) =>
      (monthly != null &&
          (monthly!.isBudgetUsedUp || monthly!.leftTodayMinor <= 0)) ||
      (untilNext != null &&
          (untilNext!.runsOutEarly || untilNext!.leftTodayMinor <= 0)) ||
      failingCharges;
}

final homeSafeProvider = Provider<HomeSafe>((ref) {
  final monthlySafe = ref.watch(safeToSpendTodayProvider).value;
  final sources =
      ref.watch(incomeSourcesProvider).value ?? const IncomeSources({});
  // A salary alone keeps the monthly figure; everyone else plans until the
  // next money.
  final monthly =
      monthlySafe != null &&
          monthlyPlanFits(sources, hasBudget: monthlySafe.budgetMinor > 0)
      ? monthlySafe
      : null;
  return HomeSafe(
    monthly: monthly,
    untilNext: monthly == null ? ref.watch(untilNextMoneyProvider).value : null,
  );
});

/// Whether money is tight today (see [HomeSafe.tight]).
final homeMoneyTightProvider = Provider<bool>((ref) {
  final forecast = ref.watch(cashFlowForecastProvider).value;
  return ref
      .watch(homeSafeProvider)
      .tight(failingCharges: forecast?.failingCharges.isNotEmpty ?? false);
});
