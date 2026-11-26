import '../debts/debt.dart';
import '../enums.dart';
import '../subscriptions/subscriptions.dart';
import '../time/calendar.dart';
import '../time/week_start.dart';
import 'month_plan.dart';

/// Where a calendar bill comes from.
enum CalendarBillSource { plan, subscription, debt }

/// Whether a calendar bill is paid.
enum CalendarBillState { unpaid, late, paid }

/// One payment due on a day of the bills calendar.
class CalendarBill {
  const CalendarBill({
    required this.name,
    required this.detail,
    required this.amountMinor,
    required this.date,
    required this.state,
    required this.source,
    this.paidOn,
    this.line,
    this.categoryName,
    this.paidMinor = 0,
  });

  /// What has been paid towards it, for a bill from Plan.
  final int paidMinor;

  final String name;

  /// Where it comes from, such as `Plan · School`.
  final String detail;
  final int amountMinor;
  final CalendarDate date;
  final CalendarBillState state;
  final CalendarBillSource source;

  /// The day it was paid, when known.
  final CalendarDate? paidOn;

  /// The plan line, for a bill from Plan.
  final PlanLine? line;
  final String? categoryName;
}

/// One month of bills by due date: Plan's dated bills, tracked
/// subscriptions and loan instalments. Income and day-to-day budgets stay
/// off it.
class BillsMonth {
  const BillsMonth(this.month, this.byDay);

  /// Builds [month]'s calendar. A subscription or loan with the same name as
  /// a Plan bill shows once, as the Plan bill.
  factory BillsMonth.of({
    required MonthReview review,
    required CalendarDate today,
    Map<int, String> categoryNames = const {},
    List<SubscriptionLine> subscriptions = const [],
    List<Debt> debts = const [],
  }) {
    final month = review.month;
    final plan = review.plan;
    final bills = <CalendarBill>[];
    CalendarBillState stateOf(CalendarDate due) =>
        due.isBefore(today) ? CalendarBillState.late : CalendarBillState.unpaid;

    for (final category in review.categories) {
      for (final progress in category.lines) {
        final line = progress.line;
        final due = line.dueDate;
        if (due == null || !month.contains(due)) continue;
        if (plan.isDailySpending(line) || line.amountMinor <= 0) continue;
        final name = categoryNames[line.categoryId] ?? 'Uncategorised';
        bills.add(
          CalendarBill(
            name: line.name,
            detail: 'Plan · $name',
            amountMinor: line.amountMinor,
            date: due,
            state: progress.isPaid ? CalendarBillState.paid : stateOf(due),
            source: CalendarBillSource.plan,
            line: line,
            categoryName: name,
            paidMinor: progress.paidMinor,
          ),
        );
      }
    }
    final taken = {for (final b in bills) b.name.trim().toLowerCase()};
    bool fresh(String name) => taken.add(name.trim().toLowerCase());

    for (final sub in subscriptions) {
      final s = sub.subscription;
      if (s.status != SubscriptionStatus.tracking || !fresh(s.name)) continue;
      final detail = 'Subscription · ${_every(s.frequency)}';
      final last = sub.lastChargedOn;
      if (last != null && month.contains(last)) {
        bills.add(
          CalendarBill(
            name: s.name,
            detail: detail,
            amountMinor: sub.amountMinor,
            date: last,
            state: CalendarBillState.paid,
            paidOn: last,
            source: CalendarBillSource.subscription,
          ),
        );
      }
      for (
        var date = sub.nextDate;
        !date.isAfter(month.lastDay);
        date = stepDate(date, s.frequency)
      ) {
        if (date.isBefore(month.firstDay) || date == last) continue;
        bills.add(
          CalendarBill(
            name: s.name,
            detail: detail,
            amountMinor: sub.amountMinor,
            date: date,
            state: stateOf(date),
            source: CalendarBillSource.subscription,
          ),
        );
      }
    }

    for (final debt in debts) {
      if (!fresh(debt.lender)) continue;
      final detail = debt.type == DebtType.family
          ? 'Debts · family loan'
          : 'Debts · instalment';
      CalendarBill bill(
        CalendarDate date,
        int amount,
        CalendarBillState state, {
        CalendarDate? paidOn,
      }) => CalendarBill(
        name: debt.lender,
        detail: detail,
        amountMinor: amount,
        date: date,
        state: state,
        paidOn: paidOn,
        source: CalendarBillSource.debt,
      );

      final paid = debt.lastPayment;
      var paidShown = false;
      if (debt.instalments.isNotEmpty) {
        for (final i in debt.instalments) {
          if (month.contains(i.dueDate)) {
            bills.add(bill(i.dueDate, i.amountMinor, stateOf(i.dueDate)));
          }
        }
      } else if (debt.nextDue case final next? when month.contains(next.date)) {
        final amount = debt.minimumPaymentMinor > 0
            ? debt.minimumPaymentMinor
            : paid?.amountMinor ?? 0;
        if (amount > 0) {
          if (next.paidSince) {
            paidShown = true;
            bills.add(
              bill(
                next.date,
                amount,
                CalendarBillState.paid,
                paidOn: paid?.date,
              ),
            );
          } else if (debt.balanceMinor > 0) {
            bills.add(bill(next.date, amount, stateOf(next.date)));
          }
        }
      }
      if (!paidShown && paid != null && month.contains(paid.date)) {
        bills.add(
          bill(
            paid.date,
            paid.amountMinor,
            CalendarBillState.paid,
            paidOn: paid.date,
          ),
        );
      }
    }

    final byDay = <CalendarDate, List<CalendarBill>>{};
    for (final b in bills) {
      (byDay[b.date] ??= []).add(b);
    }
    return BillsMonth(month, byDay);
  }

  final YearMonth month;
  final Map<CalendarDate, List<CalendarBill>> byDay;

  List<CalendarBill> on(CalendarDate date) => byDay[date] ?? const [];

  /// Whether [date] has something still to pay; null when nothing is due
  /// that day.
  bool? stillDueOn(CalendarDate date) {
    final bills = byDay[date];
    if (bills == null || bills.isEmpty) return null;
    return bills.any((b) => b.state != CalendarBillState.paid);
  }
}

/// The days a month grid shows, from the first day of the week on or
/// before the 1st to the last day of the week on or after the month's last
/// day (weeks start on [weekStartsOn], see [FirstWeekday]).
List<CalendarDate> calendarGridDays(YearMonth month, {int? weekStartsOn}) {
  final start = weekStartOn(month.firstDay, weekStartsOn);
  final end = weekEndOn(month.lastDay, weekStartsOn);
  return [for (var d = start; !d.isAfter(end); d = d.addDays(1)) d];
}

String _every(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.weekly => 'every week',
  RecurrenceFrequency.monthly => 'every month',
  RecurrenceFrequency.quarterly => 'every three months',
  RecurrenceFrequency.yearly => 'every year',
};
