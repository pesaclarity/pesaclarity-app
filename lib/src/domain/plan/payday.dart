import '../../core/money/money.dart';
import '../debts/debt.dart';
import '../debts/payday_split.dart';
import '../debts/payoff_order.dart';
import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';
import 'month_plan.dart';
import 'surplus_split.dart';

/// The seeded category key for salary.
const salaryKey = 'salary';

/// How many days after a payday the checklist is still offered.
const paydayWindowDays = 7;

/// A payday that has arrived: income that landed, or the planned salary date.
class Payday {
  const Payday({
    required this.date,
    required this.amountMinor,
    required this.fromMessage,
  });

  final CalendarDate date;

  /// What landed this month, or the expected income when nothing has yet.
  final int amountMinor;

  /// True when income actually arrived; false when only the planned date
  /// has come.
  final bool fromMessage;
}

/// Finds this month's payday at [today], or null outside the payday window.
///
/// Salary counts when it lands in the plan's month and no more than
/// [paydayWindowDays] ago: income in the Salary category, in a category the
/// plan expects income from, or at least half the plan's expected income.
/// Its amount is all such income in the month so far. Without one, the day a
/// planned income line falls due counts, for the same window.
Payday? detectPayday({
  required MonthPlan plan,
  required Iterable<LedgerEntry> entries,
  required CalendarDate today,
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  final month = plan.month;
  if (!month.contains(today)) return null;
  final windowStart = today.addDays(-paydayWindowDays);
  final expected = plan.expectedIncomeMinor;
  final incomeCategories = {for (final l in plan.incomeLines) l.categoryId};

  bool isSalary(LedgerEntry e) {
    if (!e.isInflow || roleOf(e) != LedgerRole.income) return false;
    if (e.currency != currency || !month.contains(e.date)) return false;
    if (e.date.isAfter(today)) return false;
    final category = plan.categories[e.categoryId];
    if (category?.key == salaryKey) return true;
    if (e.categoryId != null && incomeCategories.contains(e.categoryId)) {
      return true;
    }
    return expected > 0 && e.amountMinor * 2 >= expected;
  }

  final salaries = entries.where(isSalary).toList();
  if (salaries.isNotEmpty) {
    final latest = salaries
        .map((e) => e.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (latest.isBefore(windowStart)) return null;
    return Payday(
      date: latest,
      amountMinor: salaries.fold(0, (s, e) => s + e.amountMinor),
      fromMessage: true,
    );
  }

  final due = [
    for (final line in plan.incomeLines)
      if (line.dueDate case final date?)
        if (!date.isAfter(today) && !date.isBefore(windowStart)) date,
  ];
  if (due.isEmpty || expected <= 0) return null;
  return Payday(
    date: due.reduce((a, b) => a.isBefore(b) ? a : b),
    amountMinor: expected,
    fromMessage: false,
  );
}

/// What a payday task pays for.
enum PaydayTaskKind {
  bill('Bills'),
  debt('Debts'),
  setAside('Set aside'),
  savings('Savings');

  const PaydayTaskKind(this.label);

  final String label;
}

/// One thing to do with this payday's money.
class PaydayTask {
  const PaydayTask({
    required this.key,
    required this.kind,
    required this.name,
    required this.amountMinor,
    this.dueDate,
  });

  /// Stable within the month, so a tick survives a refresh.
  final String key;
  final PaydayTaskKind kind;
  final String name;
  final int amountMinor;
  final CalendarDate? dueDate;
}

/// The proposed split of a payday: bills such as rent, debts, set-asides and
/// savings, in that order, as a checklist.
class PaydayChecklist {
  const PaydayChecklist({required this.incomeMinor, required this.tasks});

  /// Proposes how to split [incomeMinor] using [review]'s unpaid lines.
  ///
  /// Bills are unpaid lines in bill categories, by due date. Debts get their
  /// planned lines or the scheduled payments on [debts], whichever is more,
  /// plus the debt share of any surplus, split with [PaydaySplit]. Tax lines
  /// and what is left of day-to-day budgets are set aside. Savings get their
  /// planned lines plus the rest of the surplus.
  factory PaydayChecklist.propose({
    required MonthReview review,
    required int incomeMinor,
    Iterable<Debt> debts = const [],
    PayoffStrategy strategy = PayoffStrategy.avalanche,
    List<int> customOrder = const [],
    int debtShareBasisPoints = defaultDebtShareBasisPoints,
  }) {
    final plan = review.plan;
    final bills = <PaydayTask>[];
    final setAsides = <PaydayTask>[];
    final savings = <PaydayTask>[];
    final debtLines = <PaydayTask>[];
    var dayToDay = 0;

    for (final category in review.categories) {
      final type = plan.categories[category.categoryId]?.type;
      for (final progress in category.lines) {
        final line = progress.line;
        final unpaid = progress.unpaidMinor;
        if (unpaid <= 0) continue;
        if (plan.isDailySpending(line)) {
          dayToDay += unpaid;
          continue;
        }
        final task = PaydayTask(
          key: _lineKey(line),
          kind: switch (type) {
            CategoryType.debt => PaydayTaskKind.debt,
            CategoryType.tax => PaydayTaskKind.setAside,
            CategoryType.savings => PaydayTaskKind.savings,
            _ => PaydayTaskKind.bill,
          },
          name: line.name,
          amountMinor: unpaid,
          dueDate: line.dueDate,
        );
        switch (task.kind) {
          case PaydayTaskKind.bill:
            bills.add(task);
          case PaydayTaskKind.debt:
            debtLines.add(task);
          case PaydayTaskKind.setAside:
            setAsides.add(task);
          case PaydayTaskKind.savings:
            savings.add(task);
        }
      }
    }
    bills.sort(_byDueDate);
    if (dayToDay > 0) {
      setAsides.add(
        PaydayTask(
          key: 'day-to-day',
          kind: PaydayTaskKind.setAside,
          name: 'Day-to-day spending',
          amountMinor: dayToDay,
        ),
      );
    }

    final owing = [
      for (final d in debts)
        if (d.balanceMinor > 0) d,
    ];
    final plannedDebt = _sum(debtLines);
    final month = plan.month;
    final scheduled = owing.isEmpty
        ? 0
        : PaydaySplit.of(
            debts: owing,
            availableMinor: 0,
            month: month,
            strategy: strategy,
            customOrder: customOrder,
          ).shortfallMinor;
    final baseDebt = plannedDebt > scheduled ? plannedDebt : scheduled;

    final surplus = SurplusSplit.of(
      expectedIncomeMinor: incomeMinor,
      plannedOutgoingMinor:
          _sum(bills) + _sum(setAsides) + _sum(savings) + baseDebt,
      hasDebt: owing.isNotEmpty || plannedDebt > 0,
      debtShareBasisPoints: debtShareBasisPoints,
    );

    final debtTasks = <PaydayTask>[];
    var toSavings = surplus.toSavingsMinor;
    if (owing.isNotEmpty) {
      final split = PaydaySplit.of(
        debts: owing,
        availableMinor: baseDebt + surplus.toDebtMinor,
        month: month,
        strategy: strategy,
        customOrder: customOrder,
      );
      final lenders = {for (final d in owing) d.id: d.lender};
      debtTasks.addAll([
        for (final share in split.shares)
          PaydayTask(
            key: 'debt:${share.debtId}',
            kind: PaydayTaskKind.debt,
            name: lenders[share.debtId]!,
            amountMinor: share.totalMinor,
          ),
      ]);
      toSavings += split.unallocatedMinor;
    } else {
      debtTasks.addAll(debtLines..sort(_byDueDate));
      if (surplus.toDebtMinor > 0) {
        debtTasks.add(
          PaydayTask(
            key: 'surplus:debt',
            kind: PaydayTaskKind.debt,
            name: 'Extra to debt',
            amountMinor: surplus.toDebtMinor,
          ),
        );
      }
    }
    if (toSavings > 0) {
      savings.add(
        PaydayTask(
          key: 'surplus:savings',
          kind: PaydayTaskKind.savings,
          name: 'Surplus to savings',
          amountMinor: toSavings,
        ),
      );
    }

    return PaydayChecklist(
      incomeMinor: incomeMinor,
      tasks: List.unmodifiable([
        ...bills,
        ...debtTasks,
        ...setAsides,
        ...savings,
      ]),
    );
  }

  final int incomeMinor;
  final List<PaydayTask> tasks;

  int get plannedMinor => _sum(tasks);

  /// How much the tasks need beyond the income; zero when it covers them.
  int get shortfallMinor =>
      plannedMinor > incomeMinor ? plannedMinor - incomeMinor : 0;

  /// Whether every task key is in [ticked].
  bool isComplete(Set<String> ticked) =>
      tasks.every((t) => ticked.contains(t.key));
}

String _lineKey(PlanLine line) =>
    'line:${line.source.name}:${line.sourceId ?? line.name}'
    '${line.dueDate == null ? '' : ':${line.dueDate}'}';

int _byDueDate(PaydayTask a, PaydayTask b) {
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue == null && bDue == null) return 0;
  if (aDue == null) return 1;
  if (bDue == null) return -1;
  return aDue.compareTo(bDue);
}

int _sum(Iterable<PaydayTask> tasks) =>
    tasks.fold(0, (s, t) => s + t.amountMinor);
