import '../../core/money/money.dart';
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
/// budget before the month ends.
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
  });

  /// Works out today's limits.
  ///
  /// [budgetMinor] is this month's day-to-day budget. [entries] may hold any
  /// period: only day-to-day spending in [today]'s Nairobi month, up to and
  /// including today, counts. Refunds in day-to-day categories reduce it.
  factory SafeToSpend.calculate({
    required int budgetMinor,
    required Iterable<LedgerEntry> entries,
    required CalendarDate today,
    int weekendWeightPercent = evenWeekendWeightPercent,
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    if (weekendWeightPercent <= 0) {
      throw ArgumentError.value(
        weekendWeightPercent,
        'weekendWeightPercent',
        'must be positive',
      );
    }
    final month = today.yearMonth;
    var before = 0;
    var onToday = 0;
    for (final entry in entries) {
      if (entry.currency != currency) continue;
      final date = entry.date;
      if (!month.contains(date) || date.isAfter(today)) continue;
      final amount = dayToDaySpendOf(entry);
      if (date == today) {
        onToday += amount;
      } else {
        before += amount;
      }
    }

    var weekdays = 0;
    var weekendDays = 0;
    for (var d = today; month.contains(d); d = d.addDays(1)) {
      d.isWeekend ? weekendDays++ : weekdays++;
    }

    final left = budgetMinor - before;
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
    );
  }

  final CalendarDate today;
  final int budgetMinor;
  final int spentBeforeTodayMinor;
  final int spentTodayMinor;

  /// Weekdays left in the month, today included.
  final int weekdaysLeft;

  /// Saturdays and Sundays left in the month, today included.
  final int weekendDaysLeft;
  final int weekdayLimitMinor;
  final int weekendLimitMinor;

  /// Today's limit: the weekend limit on Saturday and Sunday.
  int get todayLimitMinor =>
      today.isWeekend ? weekendLimitMinor : weekdayLimitMinor;

  /// Safe to spend for the rest of today; never negative.
  int get leftTodayMinor {
    final left = todayLimitMinor - spentTodayMinor;
    return left > 0 ? left : 0;
  }

  /// How far today's spending has gone past today's limit.
  int get overTodayMinor {
    final over = spentTodayMinor - todayLimitMinor;
    return over > 0 ? over : 0;
  }

  /// Day-to-day budget left this month after today's spending. Negative when
  /// the budget is overspent.
  int get leftThisMonthMinor =>
      budgetMinor - spentBeforeTodayMinor - spentTodayMinor;

  /// The budget was used up before today started.
  bool get isBudgetUsedUp => budgetMinor - spentBeforeTodayMinor <= 0;
}

/// What [entry] adds to day-to-day spending: its amount for spending in a
/// day-to-day category, minus that for a refund in one, otherwise zero.
int dayToDaySpendOf(LedgerEntry entry) {
  if (!entry.isDailySpending) return 0;
  return switch (roleOf(entry)) {
    LedgerRole.spending => entry.amountMinor,
    LedgerRole.reversal when entry.isInflow => -entry.amountMinor,
    _ => 0,
  };
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
