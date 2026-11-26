import '../../core/money/money.dart';
import '../income/payday.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';

/// Weekend days get the same limit as weekdays unless history says otherwise.
const evenWeekendWeightPercent = 100;

/// Bounds for a weekend weight learnt from history, so one odd month cannot
/// starve weekdays or weekends.
const minWeekendWeightPercent = 50;
const maxWeekendWeightPercent = 300;

/// How much the user can spend today without running out of their day-to-day
/// budget before the period ends: the pay cycle when there is a regular
/// payday (see [payCycleOf]), otherwise the calendar month.
///
/// The limits are worked out from what was left at the start of today, so
/// spending during the day lowers [leftTodayMinor] but not the limits
/// themselves. The days left include today. A weekend day's limit is the
/// weekday limit scaled by the weekend weight; both are rounded down so the
/// limits for the rest of the month never add up to more than is left.
class SafeToSpend {
  const SafeToSpend({
    required this.today,
    required this.budgetMinor,
    required this.spentBeforeTodayMinor,
    required this.spentTodayMinor,
    required this.weekdaysLeft,
    required this.weekendDaysLeft,
    required this.weekdayLimitMinor,
    required this.weekendLimitMinor,
    this.onHandMinor,
    this.goalsKeptMinor = 0,
    this.periodFirst,
    this.periodLast,
    this.payCycle = false,
  });

  /// Works out today's limits.
  ///
  /// [budgetMinor] is the period's day-to-day budget. The period runs from
  /// [periodFirst] to [periodLast] (a pay cycle, see [payCycleOf]); without
  /// them it is [today]'s calendar month. [entries] may hold any period:
  /// only day-to-day spending in the period, up to and including today,
  /// counts. Refunds in day-to-day categories reduce it.
  ///
  /// With goals kept aside ([goalsKeptMinor], already taken off
  /// [onHandMinor]), the days ahead share no more than the free money on
  /// hand, so the plan never offers what is set aside.
  factory SafeToSpend.calculate({
    required int budgetMinor,
    required Iterable<LedgerEntry> entries,
    required CalendarDate today,
    int weekendWeightPercent = evenWeekendWeightPercent,
    String? currency,
    int? onHandMinor,
    int goalsKeptMinor = 0,
    CalendarDate? periodFirst,
    CalendarDate? periodLast,
  }) {
    currency ??= BaseCurrency.code;
    final payCycle = periodFirst != null && periodLast != null;
    final first = payCycle ? periodFirst : today.yearMonth.firstDay;
    final last = payCycle ? periodLast : today.yearMonth.lastDay;
    if (today.isBefore(first) || today.isAfter(last)) {
      throw ArgumentError.value(today, 'today', 'must be in the period');
    }
    bool inPeriod(CalendarDate d) => !d.isBefore(first) && !d.isAfter(last);
    if (weekendWeightPercent <= 0) {
      throw ArgumentError.value(
        weekendWeightPercent,
        'weekendWeightPercent',
        'must be positive',
      );
    }
    var before = 0;
    var onToday = 0;
    for (final entry in entries) {
      if (entry.currency != currency) continue;
      final date = entry.date;
      if (!inPeriod(date) || date.isAfter(today)) continue;
      final amount = dayToDaySpendOf(entry);
      if (date == today) {
        onToday += amount;
      } else {
        before += amount;
      }
    }

    var weekdays = 0;
    var weekendDays = 0;
    for (var d = today; inPeriod(d); d = d.addDays(1)) {
      d.isWeekend ? weekendDays++ : weekdays++;
    }

    var left = budgetMinor - before;
    if (goalsKeptMinor > 0 && onHandMinor != null && onHandMinor < left) {
      left = onHandMinor;
    }
    var weekdayLimit = 0;
    var weekendLimit = 0;
    if (left > 0) {
      final shares =
          weekdays * evenWeekendWeightPercent +
          weekendDays * weekendWeightPercent;
      weekdayLimit = left * evenWeekendWeightPercent ~/ shares;
      weekendLimit = left * weekendWeightPercent ~/ shares;
    }

    return SafeToSpend(
      today: today,
      budgetMinor: budgetMinor,
      spentBeforeTodayMinor: before,
      spentTodayMinor: onToday,
      weekdaysLeft: weekdays,
      weekendDaysLeft: weekendDays,
      weekdayLimitMinor: weekdayLimit,
      weekendLimitMinor: weekendLimit,
      onHandMinor: onHandMinor,
      goalsKeptMinor: goalsKeptMinor,
      periodFirst: first,
      periodLast: last,
      payCycle: payCycle,
    );
  }

  final CalendarDate today;

  /// The period's first and last days, when worked out by [calculate].
  final CalendarDate? periodFirst;
  final CalendarDate? periodLast;

  /// Whether the period is a pay cycle rather than the calendar month.
  final bool payCycle;
  final int budgetMinor;
  final int spentBeforeTodayMinor;
  final int spentTodayMinor;

  /// Weekdays left in the period, today included.
  final int weekdaysLeft;

  /// Saturdays and Sundays left in the period, today included.
  final int weekendDaysLeft;
  final int weekdayLimitMinor;
  final int weekendLimitMinor;

  /// Day-to-day money on hand, Fuliza owed taken off, when known. At or
  /// below zero nothing is safe to spend, whatever the budget has left.
  final int? onHandMinor;

  /// What goals kept aside hold, already out of [onHandMinor].
  final int goalsKeptMinor;

  /// Whether the free money is used up and only what is set aside for
  /// goals is left: nothing is safe to spend, but nothing is below zero.
  bool get nothingFreeAfterGoals => goalsKeptMinor > 0 && onHandMinor == 0;

  /// Whether the accounts hold nothing to spend.
  bool get nothingOnHand => onHandMinor != null && onHandMinor! <= 0;

  /// Today's limit: the weekend limit on Saturday and Sunday.
  int get todayLimitMinor =>
      today.isWeekend ? weekendLimitMinor : weekdayLimitMinor;

  /// Safe to spend for the rest of today; never negative.
  int get leftTodayMinor {
    if (nothingOnHand) return 0;
    final left = todayLimitMinor - spentTodayMinor;
    return left > 0 ? left : 0;
  }

  /// How far today's spending has gone past today's limit.
  int get overTodayMinor {
    final over = spentTodayMinor - todayLimitMinor;
    return over > 0 ? over : 0;
  }

  /// Day-to-day budget left this period (pay cycle or month) after today's
  /// spending. Negative when the budget is overspent.
  int get leftThisMonthMinor =>
      budgetMinor - spentBeforeTodayMinor - spentTodayMinor;

  /// The budget was used up before today started.
  bool get isBudgetUsedUp => budgetMinor - spentBeforeTodayMinor <= 0;
}

/// The pay cycle [today] falls in: from [payday]'s last arrival to the day
/// before the next expected one, or to today once that is overdue. Null
/// without a regular payday, when the calendar month is used instead.
({CalendarDate first, CalendarDate last})? payCycleOf(
  Payday? payday, {
  required CalendarDate today,
}) {
  if (payday == null || payday.last.isAfter(today)) return null;
  final end = payday.last.addDays(payday.gapDays - 1);
  return (first: payday.last, last: end.isBefore(today) ? today : end);
}

/// A monthly day-to-day budget prorated to the days [first] to [last]: the
/// budget times the period's days over the days from [first] to the same
/// day a month later, so a monthly pay cycle gets the whole budget and a
/// fortnight about half. A cycle of 28 to 31 days is a month's pay and
/// keeps the whole budget. Rounded down.
int prorateMonthlyBudget(
  int monthlyMinor, {
  required CalendarDate first,
  required CalendarDate last,
}) {
  final days = first.daysUntil(last) + 1;
  if (days >= 28 && days <= 31) return monthlyMinor;
  final monthLater = _sameDayNextMonth(first);
  final monthDays = first.daysUntil(monthLater);
  return monthlyMinor * days ~/ monthDays;
}

/// The same day of the month after [d], or that month's last day.
CalendarDate _sameDayNextMonth(CalendarDate d) {
  final next = d.yearMonth.next;
  final day = d.day > next.dayCount ? next.dayCount : d.day;
  return CalendarDate(next.year, next.month, day);
}

/// What [entry] adds to day-to-day spending: its amount for spending in a
/// day-to-day category, minus that for a refund in one, otherwise zero.
int dayToDaySpendOf(LedgerEntry entry) {
  if (!entry.isDailySpending) return 0;
  return spendingOf(entry);
}

/// Learns how much more the user spends on a weekend day than a weekday.
///
/// Compares average day-to-day spending per weekend day and per weekday over
/// the four full weeks before [today], counting days with no spending as
/// zero. Returns [evenWeekendWeightPercent] when either side has no spending,
/// and otherwise a percentage clamped to [minWeekendWeightPercent] and
/// [maxWeekendWeightPercent].
int weekendWeightFromHistory(
  Iterable<LedgerEntry> entries, {
  required CalendarDate today,
  String? currency,
}) {
  currency ??= BaseCurrency.code;
  const days = 28;
  final first = today.addDays(-days);
  var weekdaySpend = 0;
  var weekendSpend = 0;
  for (final entry in entries) {
    if (entry.currency != currency) continue;
    final date = entry.date;
    if (date.isBefore(first) || !date.isBefore(today)) continue;
    final amount = dayToDaySpendOf(entry);
    if (date.isWeekend) {
      weekendSpend += amount;
    } else {
      weekdaySpend += amount;
    }
  }
  if (weekdaySpend <= 0 || weekendSpend <= 0) return evenWeekendWeightPercent;

  // Four full weeks hold 20 weekdays and 8 weekend days.
  final numerator = weekendSpend * 20 * 100;
  final denominator = weekdaySpend * 8;
  final percent = (numerator + denominator ~/ 2) ~/ denominator;
  if (percent < minWeekendWeightPercent) return minWeekendWeightPercent;
  if (percent > maxWeekendWeightPercent) return maxWeekendWeightPercent;
  return percent;
}
