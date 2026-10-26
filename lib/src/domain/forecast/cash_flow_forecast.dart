import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../plan/month_plan.dart';
import '../time/calendar.dart';

/// Days of history behind the spending pace: four full weeks, so weekdays
/// and weekends are both sampled evenly.
const paceWindowDays = 28;

/// Average day-to-day outflow per weekday and per weekend day.
///
/// Counts spending and fees in the [paceWindowDays] before today, less
/// refunds, but leaves out spending in categories that have a scheduled plan
/// line (rent, loan payments), since the forecast takes those from the plan.
/// Uncategorised spending always counts. Transaction costs count on every
/// entry. When the window holds no weekday or no weekend day, both use the
/// window's overall average.
class SpendingPace {
  const SpendingPace({required this.weekdayMinor, required this.weekendMinor});

  /// [historyFrom] is the first day the ledger covers; the window starts no
  /// earlier, so a new user's average is not diluted by empty days.
  factory SpendingPace.fromHistory(
    Iterable<LedgerEntry> entries, {
    required CalendarDate today,
    Set<int> scheduledCategoryIds = const {},
    CalendarDate? historyFrom,
    String currency = 'KES',
  }) {
    var start = today.addDays(-paceWindowDays);
    if (historyFrom != null && historyFrom.isAfter(start)) start = historyFrom;

    var weekdays = 0;
    var weekendDays = 0;
    for (var d = start; d.isBefore(today); d = d.addDays(1)) {
      d.isWeekend ? weekendDays++ : weekdays++;
    }

    var weekdaySpend = 0;
    var weekendSpend = 0;
    for (final e in entries) {
      if (e.currency != currency) continue;
      final date = e.date;
      if (date.isBefore(start) || !date.isBefore(today)) continue;
      final amount = paceSpendOf(e, scheduledCategoryIds);
      if (date.isWeekend) {
        weekendSpend += amount;
      } else {
        weekdaySpend += amount;
      }
    }

    final days = weekdays + weekendDays;
    if (days == 0) return const SpendingPace(weekdayMinor: 0, weekendMinor: 0);
    final overall = _atLeastZero((weekdaySpend + weekendSpend) ~/ days);
    return SpendingPace(
      weekdayMinor: weekdays == 0
          ? overall
          : _atLeastZero(weekdaySpend ~/ weekdays),
      weekendMinor: weekendDays == 0
          ? overall
          : _atLeastZero(weekendSpend ~/ weekendDays),
    );
  }

  final int weekdayMinor;
  final int weekendMinor;

  int on(CalendarDate date) => date.isWeekend ? weekendMinor : weekdayMinor;
}

/// What [entry] adds to the spending pace; see [SpendingPace].
int paceSpendOf(LedgerEntry entry, Set<int> scheduledCategoryIds) {
  var amount = entry.feeMinor;
  final role = roleOf(entry);
  if (role == LedgerRole.fee) return amount + entry.amountMinor;
  if (scheduledCategoryIds.contains(entry.categoryId)) return amount;
  if (role == LedgerRole.spending) amount += entry.amountMinor;
  if (role == LedgerRole.reversal && entry.isInflow) {
    amount -= entry.amountMinor;
  }
  return amount;
}

/// A known amount still to come in or go out this month.
class ScheduledFlow {
  const ScheduledFlow({
    required this.name,
    required this.date,
    required this.amountMinor,
    required this.isIncome,
  });

  final String name;
  final CalendarDate date;
  final int amountMinor;
  final bool isIncome;
}

/// One day of the forecast.
class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.openingMinor,
    required this.incomeMinor,
    required this.chargesMinor,
    required this.spendingMinor,
  });

  final CalendarDate date;
  final int openingMinor;
  final int incomeMinor;
  final int chargesMinor;
  final int spendingMinor;

  int get closingMinor =>
      openingMinor + incomeMinor - chargesMinor - spendingMinor;
}

/// A charge the balance would not cover on its due date.
class FailingCharge {
  const FailingCharge({
    required this.name,
    required this.date,
    required this.amountMinor,
    required this.balanceBeforeMinor,
  });

  final String name;
  final CalendarDate date;
  final int amountMinor;

  /// The projected balance just before the charge.
  final int balanceBeforeMinor;

  int get shortMinor => amountMinor - balanceBeforeMinor;
}

/// The day-by-day balance from today to the end of the month.
///
/// Each day takes expected income first, then that day's charges (debit
/// orders and standing orders usually run early), then the day's spending at
/// the [SpendingPace]. Today's spending is the pace less what has already
/// been spent today. A charge fails when the balance before it is below its
/// amount; it is still taken off, since a failed charge is usually retried
/// or still owed, so later days show the shortfall.
class CashFlowForecast {
  const CashFlowForecast({
    required this.today,
    required this.startingBalanceMinor,
    required this.pace,
    required this.scheduled,
    required this.days,
    required this.failingCharges,
    this.currency = 'KES',
  });

  /// Projects from [balanceMinor], the balance of day-to-day accounts now.
  ///
  /// [entries] should cover today's month and the [paceWindowDays] before
  /// today. Scheduled flows come from [plan], which must be today's month;
  /// see [scheduledFlows].
  factory CashFlowForecast.project({
    required int balanceMinor,
    required CalendarDate today,
    required MonthPlan plan,
    required Iterable<LedgerEntry> entries,
    CalendarDate? historyFrom,
    String currency = 'KES',
  }) {
    if (!plan.month.contains(today)) {
      throw ArgumentError.value(plan.month, 'plan', 'must be today\'s month');
    }
    final list = entries.where((e) => e.currency == currency).toList();
    final scheduledIds = scheduledCategoryIds(plan);
    final pace = SpendingPace.fromHistory(
      list,
      today: today,
      scheduledCategoryIds: scheduledIds,
      historyFrom: historyFrom,
      currency: currency,
    );
    final spentToday = list
        .where((e) => e.date == today)
        .fold(0, (sum, e) => sum + paceSpendOf(e, scheduledIds));
    final flows = scheduledFlows(plan, list, today: today, currency: currency);

    final days = <ForecastDay>[];
    final failing = <FailingCharge>[];
    var balance = balanceMinor;
    for (var d = today; plan.month.contains(d); d = d.addDays(1)) {
      final opening = balance;
      final onDay = flows.where((f) => f.date == d);
      var income = 0;
      for (final f in onDay.where((f) => f.isIncome)) {
        income += f.amountMinor;
      }
      balance += income;
      var charges = 0;
      for (final f in onDay.where((f) => !f.isIncome)) {
        if (balance < f.amountMinor) {
          failing.add(
            FailingCharge(
              name: f.name,
              date: d,
              amountMinor: f.amountMinor,
              balanceBeforeMinor: balance,
            ),
          );
        }
        balance -= f.amountMinor;
        charges += f.amountMinor;
      }
      final spending = d == today
          ? _atLeastZero(pace.on(d) - spentToday)
          : pace.on(d);
      balance -= spending;
      days.add(
        ForecastDay(
          date: d,
          openingMinor: opening,
          incomeMinor: income,
          chargesMinor: charges,
          spendingMinor: spending,
        ),
      );
    }

    return CashFlowForecast(
      today: today,
      startingBalanceMinor: balanceMinor,
      pace: pace,
      scheduled: List.unmodifiable(flows),
      days: List.unmodifiable(days),
      failingCharges: List.unmodifiable(failing),
      currency: currency,
    );
  }

  final CalendarDate today;
  final int startingBalanceMinor;
  final SpendingPace pace;
  final List<ScheduledFlow> scheduled;

  /// Today to the month's last day.
  final List<ForecastDay> days;
  final List<FailingCharge> failingCharges;
  final String currency;

  /// The first day the balance ends at or below zero; null if it never does
  /// this month.
  CalendarDate? get zeroDate {
    for (final day in days) {
      if (day.closingMinor <= 0) return day.date;
    }
    return null;
  }

  int get monthEndBalanceMinor => days.last.closingMinor;

  /// The forecast in plain words: when the money runs out (or what is left
  /// at month end), then each charge that may not go through.
  List<String> get messages {
    String money(int minor) => formatMoney(Money(minor, currency: currency));
    String when(CalendarDate date) =>
        date == today ? 'today' : 'on the ${ordinalDay(date.day)}';

    final zero = zeroDate;
    return [
      if (zero != null)
        'At this pace you hit zero ${when(zero)}.'
      else
        'At this pace you end the month with ${money(monthEndBalanceMinor)}.',
      for (final c in failingCharges)
        'Your ${c.name} payment of ${money(c.amountMinor)} ${when(c.date)} '
            'may not go through. You would be ${money(c.shortMinor)} short.',
    ];
  }
}

/// Categories whose spending comes from the plan rather than the pace:
/// those with an outgoing line that is not a day-to-day budget.
Set<int> scheduledCategoryIds(MonthPlan plan) => {
  for (final line in plan.outgoingLines)
    if (!plan.isDailySpending(line)) ?line.categoryId,
};

/// Known flows still to come in [plan]'s month, from [today] on.
///
/// Outgoings are the unpaid part of each line that is not a day-to-day
/// budget (the pace covers those), after [MonthReview] has matched this
/// month's payments. An overdue line is placed today; an undated one-off or
/// arrear on the month's last day, so it counts against the month-end
/// balance without inventing an earlier date.
///
/// Income is each income line not yet received: a category's income this
/// month is matched to its lines by due date. Only lines due today or later
/// count; late or undated income is left out rather than counted on.
List<ScheduledFlow> scheduledFlows(
  MonthPlan plan,
  Iterable<LedgerEntry> entries, {
  required CalendarDate today,
  String currency = 'KES',
}) {
  final month = plan.month;
  final inMonth = entries
      .where((e) => e.currency == currency && month.contains(e.date))
      .toList();
  final flows = <ScheduledFlow>[];

  final review = MonthReview.of(plan, inMonth, currency: currency);
  for (final category in review.categories) {
    for (final progress in category.lines) {
      final line = progress.line;
      if (progress.unpaidMinor <= 0 || plan.isDailySpending(line)) continue;
      final due = line.dueDate;
      flows.add(
        ScheduledFlow(
          name: line.name,
          date: due == null
              ? month.lastDay
              : (due.isBefore(today) ? today : due),
          amountMinor: progress.unpaidMinor,
          isIncome: false,
        ),
      );
    }
  }

  final received = <int?, int>{};
  for (final e in inMonth) {
    if (roleOf(e) == LedgerRole.income && e.isInflow) {
      received[e.categoryId] = (received[e.categoryId] ?? 0) + e.amountMinor;
    }
  }
  final incomeLines = plan.incomeLines.toList()..sort(_byDueDate);
  for (final line in incomeLines) {
    final available = received[line.categoryId] ?? 0;
    final matched = available < line.amountMinor ? available : line.amountMinor;
    received[line.categoryId] = available - matched;
    final due = line.dueDate;
    final left = line.amountMinor - matched;
    if (left <= 0 || due == null || due.isBefore(today)) continue;
    flows.add(
      ScheduledFlow(
        name: line.name,
        date: due,
        amountMinor: left,
        isIncome: true,
      ),
    );
  }

  // List.sort is not stable; keep plan order within a day.
  final order = {for (final (i, f) in flows.indexed) f: i};
  flows.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : order[a]!.compareTo(order[b]!);
  });
  return flows;
}

/// 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st, 22nd, 23rd, 31st.
String ordinalDay(int day) {
  final suffix = (day % 100 >= 11 && day % 100 <= 13)
      ? 'th'
      : switch (day % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$day$suffix';
}

int _byDueDate(PlanLine a, PlanLine b) {
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue == null) return bDue == null ? 0 : 1;
  if (bDue == null) return -1;
  return aDue.compareTo(bDue);
}

int _atLeastZero(int value) => value < 0 ? 0 : value;
