import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../ledger/ledger_totals.dart';
import '../plan/month_plan.dart';
import '../time/calendar.dart';

/// The month's measures behind the Financial Health Index, in integer minor
/// units and counts.
class HealthInputs {
  const HealthInputs({
    required this.month,
    this.incomeMinor = 0,
    this.spendingMinor = 0,
    this.billsDue = 0,
    this.billsPaidOnTime = 0,
    this.essentialsMinor = 0,
    this.savingsBalanceMinor = 0,
    this.savedMinor = 0,
    this.debtPaymentsMinor = 0,
    this.overdraftDays = 0,
    this.leakageMinor = 0,
    this.plannedCategories = 0,
    this.categoriesWithinBudget = 0,
  });

  /// Works out [plan]'s month from the ledger.
  ///
  /// [history] should start before the month so Fuliza fees are split out
  /// correctly. [savingsBalanceMinor] is what the user holds in savings
  /// accounts at the end of the month (or at [asOf]). Only bills due on or
  /// before [asOf], which defaults to the month's last day, are judged.
  ///
  /// - Spending is spending plus fees; tax, savings and debt payments are
  ///   judged by their own indicators.
  /// - A bill is a recurring line in a bill category
  ///   ([MonthPlan.isBillCategory]); it is on time when the category's
  ///   payments up to and including its due date cover it, in the same order
  ///   [MonthReview] pays lines. Payments made in the month before do not
  ///   count.
  /// - Essentials are the month's planned expense, debt and tax lines, or,
  ///   with no plan, the actual spending, fees, tax and debt payments.
  /// - Overdraft days are days with at least one Fuliza draw.
  /// - Leakages are spending with a payee leak type, plus every fee.
  /// - Plan adherence covers expense categories with a planned amount; one is
  ///   within budget when its actual is no more than planned.
  factory HealthInputs.forMonth({
    required MonthPlan plan,
    required Iterable<LedgerEntry> history,
    int savingsBalanceMinor = 0,
    CalendarDate? asOf,
    String currency = 'KES',
  }) {
    final month = plan.month;
    final entries = history.where((e) => e.currency == currency).toList();
    final totals = LedgerTotals.of(
      entries,
      from: month.startInstant,
      to: month.endInstant,
      currency: currency,
    );
    final inMonth = entries.where((e) => month.contains(e.date)).toList();
    final review = MonthReview.of(plan, inMonth, currency: currency);
    final judgedTo = asOf ?? month.lastDay;

    final bills = _billsOnTime(plan, inMonth, judgedTo, currency);

    final byType = plan.plannedByType;
    var essentials =
        (byType[CategoryType.expense] ?? 0) +
        (byType[CategoryType.debt] ?? 0) +
        (byType[CategoryType.tax] ?? 0);
    if (essentials == 0) {
      essentials =
          totals.spendingMinor +
          totals.feesMinor +
          totals.taxMinor +
          totals.debtRepaymentMinor;
    }

    final overdraftDays = {
      for (final e in inMonth)
        if (e.kind == TransactionKind.fulizaDraw) e.date,
    }.length;

    var leakage = totals.feesMinor;
    for (final e in inMonth) {
      if (e.leakType != LeakType.none && roleOf(e) == LedgerRole.spending) {
        leakage += e.amountMinor;
      }
    }

    var planned = 0;
    var within = 0;
    for (final c in review.categories) {
      if (c.plannedMinor <= 0 ||
          plan.categories[c.categoryId]?.type != CategoryType.expense) {
        continue;
      }
      planned++;
      if (c.actualMinor <= c.plannedMinor) within++;
    }

    return HealthInputs(
      month: month,
      incomeMinor: totals.incomeMinor,
      spendingMinor: totals.spendingMinor + totals.feesMinor,
      billsDue: bills.due,
      billsPaidOnTime: bills.onTime,
      essentialsMinor: essentials,
      savingsBalanceMinor: savingsBalanceMinor,
      savedMinor: totals.savingMinor,
      debtPaymentsMinor: totals.debtRepaymentMinor,
      overdraftDays: overdraftDays,
      leakageMinor: leakage,
      plannedCategories: planned,
      categoriesWithinBudget: within,
    );
  }

  final YearMonth month;
  final int incomeMinor;
  final int spendingMinor;
  final int billsDue;
  final int billsPaidOnTime;

  /// One month of essential outgoings.
  final int essentialsMinor;
  final int savingsBalanceMinor;

  /// Put into savings during the month.
  final int savedMinor;
  final int debtPaymentsMinor;
  final int overdraftDays;
  final int leakageMinor;
  final int plannedCategories;
  final int categoriesWithinBudget;
}

({int due, int onTime}) _billsOnTime(
  MonthPlan plan,
  List<LedgerEntry> inMonth,
  CalendarDate judgedTo,
  String currency,
) {
  final byDueDate = <CalendarDate, List<PlanLine>>{};
  for (final line in plan.outgoingLines) {
    final due = line.dueDate;
    if (line.source != PlanLineSource.recurring ||
        due == null ||
        due.isAfter(judgedTo) ||
        !plan.isBillCategory(line.categoryId)) {
      continue;
    }
    (byDueDate[due] ??= []).add(line);
  }

  var due = 0;
  var onTime = 0;
  for (final MapEntry(key: date, value: lines) in byDueDate.entries) {
    final review = MonthReview.of(
      plan,
      inMonth.where((e) => !e.date.isAfter(date)),
      currency: currency,
    );
    final paid = Set<PlanLine>.identity()
      ..addAll([
        for (final c in review.categories)
          for (final l in c.lines)
            if (l.isPaid) l.line,
      ]);
    for (final line in lines) {
      due++;
      if (paid.contains(line)) onTime++;
    }
  }
  return (due: due, onTime: onTime);
}
