import '../enums.dart';
import '../time/calendar.dart';

/// What the plan needs to know about a category.
class PlanCategory {
  const PlanCategory({
    required this.id,
    required this.type,
    this.isDailySpending = false,
  });

  final int id;
  final CategoryType type;

  /// Counts towards the day-to-day budget behind safe-to-spend.
  final bool isDailySpending;
}

/// A bill, budget or income that repeats, such as rent, school fees, a monthly
/// food budget or a salary.
class RecurringBill {
  const RecurringBill({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.frequency,
    required this.startDate,
    this.categoryId,
    this.endDate,
  });

  final int id;
  final String name;
  final int? categoryId;
  final int amountMinor;
  final RecurrenceFrequency frequency;

  /// The first due date; later ones follow from it.
  final CalendarDate startDate;

  /// The last day a due date may fall on, inclusive.
  final CalendarDate? endDate;

  /// Due dates that fall in [month].
  ///
  /// Monthly, quarterly and yearly bills fall on the start date's day of the
  /// month, or the month's last day when it is shorter (a bill starting on
  /// 31 January falls on 28 February). Weekly bills fall every seventh day
  /// from the start date, so a month holds four or five of them.
  List<CalendarDate> dueDatesIn(YearMonth month) {
    final dates = <CalendarDate>[];
    if (frequency == RecurrenceFrequency.weekly) {
      final offset = startDate.daysUntil(month.firstDay);
      final skip = offset <= 0 ? 0 : (offset + 6) ~/ 7;
      for (
        var date = startDate.addDays(skip * 7);
        month.contains(date);
        date = date.addDays(7)
      ) {
        dates.add(date);
      }
    } else {
      final step = switch (frequency) {
        RecurrenceFrequency.monthly => 1,
        RecurrenceFrequency.quarterly => 3,
        RecurrenceFrequency.yearly => 12,
        RecurrenceFrequency.weekly => throw StateError('unreachable'),
      };
      final months = startDate.yearMonth.monthsUntil(month);
      if (months >= 0 && months % step == 0) {
        final day = startDate.day < month.dayCount
            ? startDate.day
            : month.dayCount;
        dates.add(CalendarDate(month.year, month.month, day));
      }
    }
    final end = endDate;
    return [
      for (final date in dates)
        if (!date.isBefore(startDate) && (end == null || !date.isAfter(end)))
          date,
    ];
  }
}

/// A one-off or a carried-forward arrear in one month's plan.
class BudgetItem {
  const BudgetItem({
    required this.month,
    required this.name,
    required this.amountMinor,
    required this.kind,
    this.id,
    this.categoryId,
    this.isPaid = false,
  });

  /// Null until stored.
  final int? id;
  final YearMonth month;
  final String name;
  final int? categoryId;
  final int amountMinor;
  final BudgetItemKind kind;

  /// Marked paid by the user, for example when paid in cash.
  final bool isPaid;
}
