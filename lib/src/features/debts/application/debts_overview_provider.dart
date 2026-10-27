import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/debts/fuliza_tracker.dart';
import '../../../domain/debts/payoff_order.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/time/calendar.dart';

/// Where the chosen payoff strategy is kept.
const debtStrategySettingKey = 'debts.strategy';

/// The payoff strategy the person chose, and their own order for custom.
class DebtPreference {
  const DebtPreference({required this.strategy, required this.customOrder});

  final PayoffStrategy strategy;
  final List<int> customOrder;

  PayoffOptions options(YearMonth startMonth, {int extraMonthlyMinor = 0}) =>
      PayoffOptions(
        startMonth: startMonth,
        strategy: strategy,
        customOrder: customOrder,
        extraMonthlyMinor: extraMonthlyMinor,
      );
}

/// The chosen strategy. Before any choice, a saved custom order means custom
/// and otherwise avalanche, as before the choice existed.
final debtPreferenceProvider = FutureProvider<DebtPreference>((ref) async {
  final order = await ref.watch(debtsRepositoryProvider).customOrder();
  final saved = await ref
      .watch(appSettingsRepositoryProvider)
      .readJson(debtStrategySettingKey);
  final name = saved?['strategy'];
  final strategy = PayoffStrategy.values
      .where((s) => s.name == name)
      .firstOrNull;
  return DebtPreference(
    strategy:
        strategy ??
        (order.isEmpty ? PayoffStrategy.avalanche : PayoffStrategy.custom),
    customOrder: order,
  );
});

/// Saves [strategy]. Choosing custom without an order of their own keeps the
/// order the debts are in now.
Future<void> saveDebtStrategy(
  ProviderContainer container,
  PayoffStrategy strategy, {
  List<int> currentOrder = const [],
}) async {
  final debts = container.read(debtsRepositoryProvider);
  if (strategy == PayoffStrategy.custom &&
      (await debts.customOrder()).isEmpty &&
      currentOrder.isNotEmpty) {
    await debts.setCustomOrder(currentOrder);
  }
  await container.read(appSettingsRepositoryProvider).writeJson(
    debtStrategySettingKey,
    {'strategy': strategy.name},
  );
}

/// Everything the Debts screen shows.
class DebtsOverview {
  const DebtsOverview({
    required this.today,
    required this.debts,
    required this.startingBalances,
    required this.preference,
    required this.plan,
    required this.fuliza,
  });

  final CalendarDate today;

  /// Debts still owed, in payoff order.
  final List<Debt> debts;

  /// What was first owed on each debt, by id.
  final Map<int, int> startingBalances;

  final DebtPreference preference;

  /// The plan with today's strategy and no extra.
  final PayoffPlan plan;

  /// This month's Fuliza use; null when there was none.
  final FulizaTrackerMonth? fuliza;

  int get remainingMinor => debts.fold(0, (sum, d) => sum + d.balanceMinor);

  /// How much of [debt] is paid off, from 0 to 1.
  double paidFraction(Debt debt) {
    final start = startingBalances[debt.id] ?? 0;
    if (start <= 0 || debt.balanceMinor >= start) return 0;
    return 1 - debt.balanceMinor / start;
  }
}

final debtsOverviewProvider = FutureProvider<DebtsOverview>((ref) async {
  final now = ref.watch(clockProvider)();
  final today = CalendarDate.nairobi(now);
  final repository = ref.watch(debtsRepositoryProvider);
  final preference = await ref.watch(debtPreferenceProvider.future);
  final owed = [
    for (final d in await repository.debts(today: today))
      if (d.balanceMinor > 0) d,
  ];
  final ordered = payoffOrder(
    owed,
    preference.strategy,
    customOrder: preference.customOrder,
  );

  final month = today.yearMonth;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: month.previous.startInstant,
        to: today.addDays(1).startInstant,
      );
  final fuliza = FulizaTracker.of(entries, asOf: today).month(month);

  return DebtsOverview(
    today: today,
    debts: ordered,
    startingBalances: await repository.startingBalances(),
    preference: preference,
    plan: PayoffPlan.simulate(ordered, preference.options(month)),
    fuliza: fuliza.usage.drawCount == 0 ? null : fuliza,
  );
});
