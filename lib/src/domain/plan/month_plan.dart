import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';
import 'plan_inputs.dart';

/// Where a plan line came from.
enum PlanLineSource { recurring, oneOff, arrears }

/// One planned amount in a month: a recurring due date, a one-off or an
/// arrear carried forward.
class PlanLine {
  const PlanLine({
    required this.source,
    required this.sourceId,
    required this.name,
    required this.amountMinor,
    this.categoryId,
    this.dueDate,
    this.isMarkedPaid = false,
  });

  final PlanLineSource source;

  /// The recurring bill or budget item id; null for unsaved items.
  final int? sourceId;
  final String name;
  final int? categoryId;
  final int amountMinor;

  /// Null for one-offs and arrears, which are due any time in the month.
  final CalendarDate? dueDate;
  final bool isMarkedPaid;
}

/// The plan for one month: recurring bills plus that month's one-offs and
/// carried-forward arrears.
class MonthPlan {
  const MonthPlan({
    required this.month,
    required this.lines,
    required this.categories,
  });

  /// Builds [month]'s plan. Budget items for other months are ignored.
  factory MonthPlan.build({
    required YearMonth month,
    required Iterable<RecurringBill> recurring,
    required Iterable<BudgetItem> items,
    required Iterable<PlanCategory> categories,
  }) {
    final lines = <PlanLine>[
      for (final bill in recurring)
        for (final due in bill.dueDatesIn(month))
          PlanLine(
            source: PlanLineSource.recurring,
            sourceId: bill.id,
            name: bill.name,
            categoryId: bill.categoryId,
            amountMinor: bill.amountMinor,
            dueDate: due,
          ),
      for (final item in items)
        if (item.month == month)
          PlanLine(
            source: item.kind == BudgetItemKind.carriedArrears
                ? PlanLineSource.arrears
                : PlanLineSource.oneOff,
            sourceId: item.id,
            name: item.name,
            categoryId: item.categoryId,
            amountMinor: item.amountMinor,
            isMarkedPaid: item.isPaid,
          ),
    ];
    return MonthPlan(
      month: month,
      lines: List.unmodifiable(lines),
      categories: {for (final c in categories) c.id: c},
    );
  }

  final YearMonth month;
  final List<PlanLine> lines;
  final Map<int, PlanCategory> categories;

  /// Lines in income categories.
  Iterable<PlanLine> get incomeLines => lines.where(isIncome);

  /// Every line that is not income, uncategorised ones included.
  Iterable<PlanLine> get outgoingLines => lines.where((l) => !isIncome(l));

  bool isIncome(PlanLine line) =>
      categories[line.categoryId]?.type == CategoryType.income;

  /// Whether lines in [categoryId] are bills that are owed: expense, debt and
  /// tax categories that are not day-to-day budgets. An unspent food budget
  /// is surplus, not a debt, and missed savings are not owed to anyone.
  /// Uncategorised lines count, since they are usually bills.
  bool isBillCategory(int? categoryId) {
    if (categoryId == null) return true;
    final category = categories[categoryId];
    if (category == null || category.isDailySpending) return false;
    return switch (category.type) {
      CategoryType.expense || CategoryType.debt || CategoryType.tax => true,
      CategoryType.income ||
      CategoryType.savings ||
      CategoryType.transfer => false,
    };
  }

  bool isDailySpending(PlanLine line) =>
      categories[line.categoryId]?.isDailySpending ?? false;

  int get expectedIncomeMinor => _sum(incomeLines);

  int get plannedOutgoingMinor => _sum(outgoingLines);

  /// The pot behind safe-to-spend: lines in day-to-day categories.
  int get dayToDayBudgetMinor => _sum(lines.where(isDailySpending));

  /// Planned outgoings by category type, with uncategorised lines under
  /// [CategoryType.expense].
  Map<CategoryType, int> get plannedByType {
    final totals = <CategoryType, int>{};
    for (final line in outgoingLines) {
      final type = categories[line.categoryId]?.type ?? CategoryType.expense;
      totals[type] = (totals[type] ?? 0) + line.amountMinor;
    }
    return totals;
  }

  static int _sum(Iterable<PlanLine> lines) =>
      lines.fold(0, (sum, l) => sum + l.amountMinor);
}

/// How a category is doing against its plan. Always shown with its [label],
/// never by colour alone.
enum PlanStatus {
  done('Done'),
  inProgress('In progress'),
  over('Over');

  const PlanStatus(this.label);

  final String label;
}

/// A plan line with what has been paid towards it.
class LineProgress {
  const LineProgress(this.line, this.paidMinor);

  final PlanLine line;
  final int paidMinor;

  bool get isPaid => line.isMarkedPaid || paidMinor >= line.amountMinor;

  int get unpaidMinor => isPaid ? 0 : line.amountMinor - paidMinor;
}

/// One category's plan and actuals for the month. [categoryId] is null for
/// Uncategorised.
class CategoryProgress {
  const CategoryProgress({
    required this.categoryId,
    required this.plannedMinor,
    required this.actualMinor,
    required this.lines,
  });

  final int? categoryId;
  final int plannedMinor;
  final int actualMinor;
  final List<LineProgress> lines;

  /// Over when actuals pass the plan (unplanned spending is always over);
  /// Done when every line is paid or used up; otherwise In progress.
  PlanStatus get status {
    if (actualMinor > plannedMinor) return PlanStatus.over;
    if (lines.every((l) => l.isPaid)) return PlanStatus.done;
    return PlanStatus.inProgress;
  }

  int get leftMinor => plannedMinor - actualMinor;
}

/// A month's plan set against what actually happened.
class MonthReview {
  const MonthReview({required this.plan, required this.categories});

  /// Compares [plan] with the outgoings in [entries] whose Nairobi date falls
  /// in the plan's month.
  ///
  /// A category's actual is its spending, tax, savings and debt payments,
  /// less refunds. Uncategorised actuals count only spending and refunds, so
  /// an unnamed Fuliza repayment does not land there. Each category's actual
  /// pays its lines in order: arrears first, then by due date, then one-offs;
  /// a line marked paid counts as paid and uses up what it can.
  factory MonthReview.of(
    MonthPlan plan,
    Iterable<LedgerEntry> entries, {
    String currency = 'KES',
  }) {
    final actuals = <int?, int>{};
    for (final entry in entries) {
      if (entry.currency != currency || !plan.month.contains(entry.date)) {
        continue;
      }
      final amount = _actualOf(entry);
      if (amount != 0) {
        actuals[entry.categoryId] = (actuals[entry.categoryId] ?? 0) + amount;
      }
    }

    final linesByCategory = <int?, List<PlanLine>>{};
    for (final line in plan.outgoingLines) {
      (linesByCategory[line.categoryId] ??= []).add(line);
    }

    final categoryIds = {...linesByCategory.keys, ...actuals.keys};
    final progress = [
      for (final id in categoryIds)
        _progressOf(id, linesByCategory[id] ?? const [], actuals[id] ?? 0),
    ]..sort((a, b) => _categoryOrder(a.categoryId, b.categoryId));

    return MonthReview(plan: plan, categories: List.unmodifiable(progress));
  }

  final MonthPlan plan;
  final List<CategoryProgress> categories;

  YearMonth get month => plan.month;

  int get plannedMinor => categories.fold(0, (s, c) => s + c.plannedMinor);

  int get actualMinor => categories.fold(0, (s, c) => s + c.actualMinor);

  /// Unpaid bills to carry into next month as arrears.
  ///
  /// Only lines in bill categories (see [MonthPlan.isBillCategory]) carry
  /// forward. Each arrear keeps the line's name and category and is the
  /// unpaid part only.
  List<BudgetItem> get arrearsToCarry {
    final next = month.next;
    return [
      for (final category in categories)
        if (plan.isBillCategory(category.categoryId))
          for (final line in category.lines)
            if (line.unpaidMinor > 0)
              BudgetItem(
                month: next,
                name: line.line.name,
                categoryId: category.categoryId,
                amountMinor: line.unpaidMinor,
                kind: BudgetItemKind.carriedArrears,
              ),
    ];
  }
}

int _actualOf(LedgerEntry entry) {
  final role = roleOf(entry);
  if (role == LedgerRole.reversal && entry.isInflow) return -entry.amountMinor;
  if (!entry.isOutflow) return 0;
  if (entry.categoryId == null) {
    return role == LedgerRole.spending ? entry.amountMinor : 0;
  }
  return switch (role) {
    LedgerRole.spending ||
    LedgerRole.tax ||
    LedgerRole.saving ||
    LedgerRole.debtRepayment => entry.amountMinor,
    _ => 0,
  };
}

CategoryProgress _progressOf(
  int? categoryId,
  List<PlanLine> lines,
  int actual,
) {
  final ordered = [...lines]..sort(_lineOrder);
  var available = actual > 0 ? actual : 0;
  final progress = <LineProgress>[];
  for (final line in ordered) {
    final paid = available < line.amountMinor ? available : line.amountMinor;
    available -= paid;
    progress.add(LineProgress(line, paid));
  }
  return CategoryProgress(
    categoryId: categoryId,
    plannedMinor: lines.fold(0, (s, l) => s + l.amountMinor),
    actualMinor: actual,
    lines: List.unmodifiable(progress),
  );
}

int _lineOrder(PlanLine a, PlanLine b) {
  int rank(PlanLine l) => switch (l.source) {
    PlanLineSource.arrears => 0,
    PlanLineSource.recurring => 1,
    PlanLineSource.oneOff => 2,
  };
  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null && aDue != bDue) return aDue.compareTo(bDue);
  return (a.sourceId ?? 0).compareTo(b.sourceId ?? 0);
}

/// Categories by id, with Uncategorised last.
int _categoryOrder(int? a, int? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
