import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/payday_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/debts/payoff_order.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/plan/month_snapshot.dart';
import '../../../domain/plan/payday.dart';
import '../../../domain/plan/plan_groups.dart';
import '../../../domain/plan/surplus_split.dart';
import '../../../domain/time/calendar.dart';
import '../../home/application/cash_flow_forecast_provider.dart';
import '../../home/application/safe_to_spend_provider.dart';
import 'month_close.dart';

/// Today's month in Nairobi.
final currentMonthProvider = Provider<YearMonth>(
  (ref) => YearMonth.nairobi(ref.watch(clockProvider)()),
);

/// The month Plan is showing; starts on the current month.
class PlanMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => ref.watch(currentMonthProvider);

  void show(YearMonth month) => state = month;
}

final planMonthProvider = NotifierProvider<PlanMonth, YearMonth>(PlanMonth.new);

/// Freezes every month that ended since the last snapshot, carrying unpaid
/// bills forward as arrears. Runs once per app session; Plan waits on it.
final monthCloseProvider = FutureProvider<List<YearMonth>>((ref) async {
  final repository = ref.watch(planRepositoryProvider);
  final now = ref.watch(clockProvider)();
  final first = await repository.firstPlanMonth();
  if (first == null) return const [];
  return closeFinishedMonths(
    plan: repository,
    transactions: ref.watch(transactionsRepositoryProvider),
    firstMonth: first,
    now: now,
  );
});

/// Every category, by name, for labels and the bill form.
final planCategoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepositoryProvider).watchAll(),
);

/// One month of Plan: the plan against actuals, its groups and surplus, and
/// the frozen results once the month is closed.
class PlanView {
  const PlanView({
    required this.review,
    required this.groups,
    required this.surplus,
    required this.debtShareBasisPoints,
    required this.hasDebt,
    this.snapshot,
  });

  final MonthReview review;
  final List<PlanGroupTotal> groups;
  final SurplusSplit surplus;
  final int debtShareBasisPoints;
  final bool hasDebt;

  /// Set when the month is closed; its figures are what Plan shows then.
  final MonthSnapshot? snapshot;

  MonthPlan get plan => review.plan;

  bool get isClosed => snapshot != null;

  /// Category rows to show: frozen results for a closed month, live
  /// progress otherwise.
  List<CategoryRow> get categoryRows {
    final frozen = snapshot;
    if (frozen == null) {
      return [
        for (final c in review.categories)
          CategoryRow(
            categoryId: c.categoryId,
            plannedMinor: c.plannedMinor,
            actualMinor: c.actualMinor,
            status: c.status,
          ),
      ];
    }
    return [
      for (final c in frozen.categories)
        CategoryRow(
          categoryId: c.categoryId,
          plannedMinor: c.plannedMinor,
          actualMinor: c.actualMinor,
          status: c.actualMinor > c.plannedMinor
              ? PlanStatus.over
              : c.actualMinor >= c.plannedMinor
              ? PlanStatus.done
              : PlanStatus.inProgress,
        ),
    ];
  }
}

/// One line of the by-category list.
class CategoryRow {
  const CategoryRow({
    required this.categoryId,
    required this.plannedMinor,
    required this.actualMinor,
    required this.status,
  });

  final int? categoryId;
  final int plannedMinor;
  final int actualMinor;
  final PlanStatus status;
}

final planViewProvider = FutureProvider.family<PlanView, YearMonth>((
  ref,
  month,
) async {
  await ref.watch(monthCloseProvider.future);
  final repository = ref.watch(planRepositoryProvider);
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final plan = await repository.monthPlan(month);
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: month.startInstant, to: month.endInstant);
  final review = MonthReview.of(plan, entries);
  final debts = await ref.watch(debtsRepositoryProvider).debts(today: today);
  final hasDebt =
      debts.any((d) => d.balanceMinor > 0) ||
      (plan.plannedByType[CategoryType.debt] ?? 0) > 0;
  final share = await repository.surplusDebtShareBasisPoints();

  return PlanView(
    review: review,
    groups: plannedGroups(plan),
    surplus: SurplusSplit.of(
      expectedIncomeMinor: plan.expectedIncomeMinor,
      plannedOutgoingMinor: plan.plannedOutgoingMinor,
      hasDebt: hasDebt,
      debtShareBasisPoints: share,
    ),
    debtShareBasisPoints: share,
    hasDebt: hasDebt,
    snapshot: await repository.snapshot(month),
  );
});

/// This month's payday and its proposed checklist, with what is ticked.
class PaydayProposal {
  const PaydayProposal({
    required this.month,
    required this.payday,
    required this.checklist,
    required this.ticked,
    required this.isDismissed,
  });

  final YearMonth month;
  final Payday payday;
  final PaydayChecklist checklist;
  final Set<String> ticked;
  final bool isDismissed;

  bool get isComplete => checklist.isComplete(ticked);

  /// Whether to offer the checklist on Plan and Home.
  bool get shouldOffer =>
      !isDismissed && !isComplete && checklist.tasks.isNotEmpty;
}

/// The payday autopilot: null outside the days after this month's payday.
final paydayProvider = FutureProvider<PaydayProposal?>((ref) async {
  await ref.watch(monthCloseProvider.future);
  final now = ref.watch(clockProvider)();
  final today = CalendarDate.nairobi(now);
  final month = today.yearMonth;
  final repository = ref.watch(planRepositoryProvider);
  final plan = await repository.monthPlan(month);
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: month.startInstant,
        to: today.addDays(1).startInstant,
      );
  final payday = detectPayday(plan: plan, entries: entries, today: today);
  if (payday == null) return null;

  final debtsRepository = ref.watch(debtsRepositoryProvider);
  final order = await debtsRepository.customOrder();
  final checklist = PaydayChecklist.propose(
    review: MonthReview.of(plan, entries),
    incomeMinor: payday.amountMinor,
    debts: await debtsRepository.debts(today: today),
    strategy: order.isEmpty ? PayoffStrategy.avalanche : PayoffStrategy.custom,
    customOrder: order,
    debtShareBasisPoints: await repository.surplusDebtShareBasisPoints(),
  );
  final store = ref.watch(paydayRepositoryProvider);
  return PaydayProposal(
    month: month,
    payday: payday,
    checklist: checklist,
    ticked: await store.ticked(month),
    isDismissed: await store.isDismissed(month),
  );
});

/// Reloads everything that reads the plan after an edit.
void refreshPlan(WidgetRef ref) {
  ref.invalidate(planViewProvider);
  ref.invalidate(paydayProvider);
  ref.invalidate(safeToSpendTodayProvider);
  ref.invalidate(cashFlowForecastProvider);
}
