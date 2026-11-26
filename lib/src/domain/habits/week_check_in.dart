import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';
import '../time/week_start.dart';
import 'no_spend_days.dart';

/// A change in spending smaller than this, in minor units (KES 100), is
/// "about the same".
const checkInSameMinor = 10000;

/// A category this far above its usual week, in minor units (KES 500), is
/// worth a suggestion.
const checkInAboveUsualMinor = 50000;

/// Weeks before this one that make a category's usual week.
const checkInUsualWeeks = 4;

/// Spending in one category over a week; a null [categoryId] is spending
/// with no category.
typedef CategoryChange = ({int? categoryId, int changeMinor});

/// The Sunday check-in: three plain lines on the week, Monday to today,
/// worked out on the phone from the records. What changed on last week,
/// one thing that went well, and one suggestion for next week.
class WeekCheckIn {
  const WeekCheckIn({
    required this.start,
    required this.end,
    required this.spentMinor,
    required this.lastWeekMinor,
    required this.noSpendDays,
    required this.noSpendBestThisMonth,
    this.mostChanged,
    this.mostDown,
    this.aboveUsual,
    this.usualMinor = 0,
  });

  /// Spending as Home counts it: leaving out Plan's bills, moves between
  /// the person's own accounts and savings. Last week covers the same
  /// days, from the first day of the week to the same weekday.
  factory WeekCheckIn.of(
    Iterable<LedgerEntry> entries, {
    required CalendarDate today,
    required NoSpendDays noSpend,
    Set<int> scheduledCategoryIds = const {},
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    final start = weekStartOn(today, noSpend.weekStartsOn);
    final days = start.daysUntil(today) + 1;
    Map<int?, int> spentBetween(CalendarDate from, int length) {
      final by = <int?, int>{};
      final to = from.addDays(length);
      for (final e in entries) {
        if (!e.isOutflow || e.currency != currency) continue;
        if (e.date.isBefore(from) || !e.date.isBefore(to)) continue;
        if (roleOf(e) != LedgerRole.spending) continue;
        if (scheduledCategoryIds.contains(e.categoryId)) continue;
        by[e.categoryId] = (by[e.categoryId] ?? 0) + e.amountMinor;
      }
      return by;
    }

    int total(Map<int?, int> by) => by.values.fold(0, (s, v) => s + v);
    final now = spentBetween(start, days);
    final before = spentBetween(start.addDays(-7), days);
    final spent = total(now);
    final last = total(before);

    // The category behind most of the change, in the change's direction.
    final change = spent - last;
    CategoryChange? most;
    CategoryChange? down;
    for (final id in {...now.keys, ...before.keys}) {
      final c = (now[id] ?? 0) - (before[id] ?? 0);
      if (change != 0 && c.sign == change.sign) {
        if (most == null || c.abs() > most.changeMinor.abs()) {
          most = (categoryId: id, changeMinor: c);
        }
      }
      if (c < 0 && (down == null || c < down.changeMinor)) {
        down = (categoryId: id, changeMinor: c);
      }
    }

    // A whole week against the usual whole week before it.
    final week = spentBetween(start, 7);
    final usual = <int?, int>{};
    for (var w = 1; w <= checkInUsualWeeks; w++) {
      for (final MapEntry(:key, :value) in spentBetween(
        start.addDays(-7 * w),
        7,
      ).entries) {
        usual[key] = (usual[key] ?? 0) + value;
      }
    }
    CategoryChange? above;
    var usualOfAbove = 0;
    for (final MapEntry(key: id, value: minor) in week.entries) {
      if (id == null) continue;
      final typical = (usual[id] ?? 0) ~/ checkInUsualWeeks;
      if (typical <= 0) continue;
      final over = minor - typical;
      if (over >= checkInAboveUsualMinor &&
          (above == null || over > above.changeMinor)) {
        above = (categoryId: id, changeMinor: over);
        usualOfAbove = typical;
      }
    }

    return WeekCheckIn(
      start: start,
      end: today,
      spentMinor: spent,
      lastWeekMinor: last,
      noSpendDays: noSpend.weekCount,
      noSpendBestThisMonth: noSpend.weekIsBestThisMonth,
      mostChanged: most,
      mostDown: down,
      aboveUsual: above,
      usualMinor: usualOfAbove,
    );
  }

  /// Monday of the week, and the last day counted.
  final CalendarDate start;
  final CalendarDate end;

  final int spentMinor;

  /// Last week over the same days.
  final int lastWeekMinor;

  final int noSpendDays;

  /// Whether no week this month had more no-spend days.
  final bool noSpendBestThisMonth;

  /// The category behind most of the change on last week.
  final CategoryChange? mostChanged;

  /// The category that came down most on last week.
  final CategoryChange? mostDown;

  /// The category furthest above its usual week, by at least
  /// [checkInAboveUsualMinor].
  final CategoryChange? aboveUsual;

  /// [aboveUsual]'s usual week.
  final int usualMinor;

  /// This week less last week's same days.
  int get changeMinor => spentMinor - lastWeekMinor;

  /// Whether the change is too small to call.
  bool get aboutTheSame => changeMinor.abs() < checkInSameMinor;
}

/// The weekly check-in shows on the last day of the week only: Sunday for
/// a week that starts on Monday.
bool isCheckInDay(CalendarDate date, [int? weekStartsOn]) =>
    date.weekday == lastWeekday(weekStartsOn);
