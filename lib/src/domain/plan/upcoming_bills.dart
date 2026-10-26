import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';
import 'month_plan.dart';

/// Days ahead that Home looks for bills.
const upcomingBillsHorizonDays = 14;

/// A bill still to pay.
class UpcomingBill {
  const UpcomingBill({
    required this.name,
    required this.amountMinor,
    this.dueDate,
    this.categoryId,
  });

  final String name;

  /// The unpaid part.
  final int amountMinor;

  /// Null for one-offs and arrears due any time in the month.
  final CalendarDate? dueDate;
  final int? categoryId;

  bool isOverdueOn(CalendarDate today) {
    final due = dueDate;
    return due != null && due.isBefore(today);
  }
}

/// Unpaid bills from [today] to [horizonDays] ahead, overdue ones first,
/// then by due date, then undated ones.
///
/// Bills are the outgoing lines of [thisMonth] that are not day-to-day
/// budgets, less what [entries] show was paid (see [MonthReview]). Undated
/// one-offs and arrears this month are included; [nextMonth]'s dated lines
/// count when they fall inside the horizon.
List<UpcomingBill> upcomingBills({
  required MonthPlan thisMonth,
  required Iterable<LedgerEntry> entries,
  required CalendarDate today,
  MonthPlan? nextMonth,
  int horizonDays = upcomingBillsHorizonDays,
  String currency = 'KES',
}) {
  final until = today.addDays(horizonDays);
  final bills = <UpcomingBill>[];

  void addFrom(MonthPlan plan, {required bool undated}) {
    final review = MonthReview.of(plan, entries, currency: currency);
    for (final category in review.categories) {
      for (final progress in category.lines) {
        final line = progress.line;
        if (progress.unpaidMinor <= 0 || plan.isDailySpending(line)) continue;
        final due = line.dueDate;
        if (due == null ? !undated : due.isAfter(until)) continue;
        bills.add(
          UpcomingBill(
            name: line.name,
            amountMinor: progress.unpaidMinor,
            dueDate: due,
            categoryId: line.categoryId,
          ),
        );
      }
    }
  }

  addFrom(thisMonth, undated: true);
  if (nextMonth != null &&
      nextMonth.month.firstDay.isBefore(until.addDays(1))) {
    addFrom(nextMonth, undated: false);
  }

  final order = {for (final (i, b) in bills.indexed) b: i};
  bills.sort((a, b) {
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue == null || bDue == null) {
      if (aDue != null) return -1;
      if (bDue != null) return 1;
    } else if (aDue != bDue) {
      return aDue.compareTo(bDue);
    }
    return order[a]!.compareTo(order[b]!);
  });
  return bills;
}
