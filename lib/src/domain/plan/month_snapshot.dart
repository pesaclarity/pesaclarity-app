import '../time/calendar.dart';
import 'month_plan.dart';
import 'plan_inputs.dart';

/// One category's frozen month-end result. [categoryId] is null for
/// Uncategorised.
class CategorySnapshot {
  const CategorySnapshot({
    required this.categoryId,
    required this.plannedMinor,
    required this.actualMinor,
  });

  final int? categoryId;
  final int plannedMinor;
  final int actualMinor;
}

/// A month's plan and actuals frozen once the month is over, so later edits
/// to bills or categories do not rewrite history, plus the arrears it hands
/// to the next month.
class MonthSnapshot {
  const MonthSnapshot({
    required this.month,
    required this.frozenAt,
    required this.categories,
    required this.carriedArrears,
  });

  /// Freezes [review]. Refuses while the month is still running in Nairobi.
  factory MonthSnapshot.freeze(MonthReview review, {required DateTime now}) {
    if (!isMonthOver(review.month, now)) {
      throw StateError('${review.month} has not ended yet');
    }
    return MonthSnapshot(
      month: review.month,
      frozenAt: now.toUtc(),
      categories: List.unmodifiable([
        for (final c in review.categories)
          CategorySnapshot(
            categoryId: c.categoryId,
            plannedMinor: c.plannedMinor,
            actualMinor: c.actualMinor,
          ),
      ]),
      carriedArrears: List.unmodifiable(review.arrearsToCarry),
    );
  }

  final YearMonth month;
  final DateTime frozenAt;
  final List<CategorySnapshot> categories;
  final List<BudgetItem> carriedArrears;
}

/// Whether [month] has ended in Nairobi at [now].
bool isMonthOver(YearMonth month, DateTime now) =>
    !now.toUtc().isBefore(month.endInstant);

/// Months that have ended but are not frozen yet, oldest first.
///
/// Starts after [lastFrozen], or at [firstMonth] when nothing is frozen.
/// Months must be frozen in this order, because each one's arrears belong in
/// the next one's plan.
List<YearMonth> monthsToFreeze({
  required YearMonth firstMonth,
  required DateTime now,
  YearMonth? lastFrozen,
}) {
  final months = <YearMonth>[];
  for (
    var month = lastFrozen?.next ?? firstMonth;
    isMonthOver(month, now);
    month = month.next
  ) {
    months.add(month);
  }
  return months;
}
