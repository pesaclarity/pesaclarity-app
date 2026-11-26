import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';
import '../time/week_start.dart';

/// Cash paid out below this, in minor units (KES 100), does not break a
/// no-spend day: a matatu fare or a snack is not a habit.
const smallCashMinor = 10000;

/// The days before today a streak can look back over.
const noSpendLookBackDays = 62;

/// Money out on a no-spend day that does not count as spending.
enum LeftOutKind {
  /// A bill in Plan.
  bill,

  /// A move between the person's own accounts.
  move,

  /// Money put into savings.
  saving,

  /// Cash under [smallCashMinor].
  smallCash,
}

/// One payment out that does not break a no-spend day, with the name it
/// shows when known, such as `KPLC` for a bill or `Chumz` for a move.
typedef LeftOut = ({LeftOutKind kind, String? name});

/// One day's spending.
class DaySpend {
  const DaySpend({
    required this.date,
    required this.spentMinor,
    this.counted = true,
    this.leftOut = const [],
  });

  final CalendarDate date;

  /// What was spent; zero on a no-spend day.
  final int spentMinor;

  /// False for today, which is not over, a day still to come, and a day
  /// before the records start.
  final bool counted;

  /// Money out that day that did not count as spending.
  final List<LeftOut> leftOut;

  bool get isNoSpend => counted && spentMinor <= 0;
}

/// No-spend days: days with no spending, leaving out bills in Plan, moves
/// between the person's own accounts, money put into savings and cash under
/// [smallCashMinor]. Today is never counted until it is over. A plain
/// count and streak, with no badges.
class NoSpendDays {
  const NoSpendDays({
    required this.today,
    required this.days,
    this.weekStartsOn = DateTime.monday,
  });

  /// Works out each day from [historyFrom] (the first day with records)
  /// to [today]. [scheduledCategoryIds] are Plan's bills; [cashAccountIds]
  /// the cash accounts, whose small payments are left out.
  factory NoSpendDays.of(
    Iterable<LedgerEntry> entries, {
    required CalendarDate today,
    required CalendarDate historyFrom,
    Set<int> scheduledCategoryIds = const {},
    Set<int> cashAccountIds = const {},
    String? currency,
    int? weekStartsOn,
  }) {
    final firstDay = weekStartsOn ?? FirstWeekday.current;
    currency ??= BaseCurrency.code;
    final first = today.addDays(-noSpendLookBackDays);
    final spent = <CalendarDate, int>{};
    final leftOut = <CalendarDate, List<LeftOut>>{};
    for (final entry in entries) {
      if (!entry.isOutflow || entry.currency != currency) continue;
      final date = entry.date;
      if (date.isBefore(first) || date.isAfter(today)) continue;
      final role = roleOf(entry);
      final name = entry.payeeName ?? entry.counterpartyName;
      final LeftOutKind? kind;
      if (role == LedgerRole.ownTransfer) {
        kind = LeftOutKind.move;
      } else if (role == LedgerRole.saving) {
        kind = LeftOutKind.saving;
      } else if (role != LedgerRole.spending) {
        continue;
      } else if (scheduledCategoryIds.contains(entry.categoryId)) {
        kind = LeftOutKind.bill;
      } else if (cashAccountIds.contains(entry.accountId) &&
          entry.amountMinor < smallCashMinor) {
        kind = LeftOutKind.smallCash;
      } else {
        kind = null;
      }
      if (kind == null) {
        spent[date] = (spent[date] ?? 0) + entry.amountMinor;
      } else {
        (leftOut[date] ??= []).add((kind: kind, name: name));
      }
    }
    final days = <DaySpend>[];
    // Through the end of this week, so the week shows its days to come.
    final last = weekStartOn(today, firstDay).addDays(6);
    for (var d = first; !d.isAfter(last); d = d.addDays(1)) {
      days.add(
        DaySpend(
          date: d,
          spentMinor: spent[d] ?? 0,
          counted: d.isBefore(today) && !d.isBefore(historyFrom),
          leftOut: leftOut[d] ?? const [],
        ),
      );
    }
    return NoSpendDays(today: today, days: days, weekStartsOn: firstDay);
  }

  final CalendarDate today;

  /// The weekday the week starts on (see [FirstWeekday]).
  final int weekStartsOn;

  /// Every day worked out, oldest first, through the end of this week.
  final List<DaySpend> days;

  /// This week, from the day it starts on.
  List<DaySpend> get week {
    final start = weekStartOn(today, weekStartsOn);
    return [
      for (final d in days)
        if (!d.date.isBefore(start) && d.date.isBefore(start.addDays(7))) d,
    ];
  }

  /// No-spend days this week so far.
  int get weekCount => week.where((d) => d.isNoSpend).length;

  /// No-spend days in a row up to yesterday.
  int get streak {
    var count = 0;
    for (final d in days.reversed) {
      if (!d.date.isBefore(today)) continue;
      if (!d.isNoSpend) break;
      count++;
    }
    return count;
  }

  /// The longest run of no-spend days within this month.
  int get longestThisMonth {
    var longest = 0;
    var run = 0;
    for (final d in days) {
      if (!today.yearMonth.contains(d.date)) continue;
      run = d.isNoSpend ? run + 1 : 0;
      if (run > longest) longest = run;
    }
    return longest;
  }

  /// No-spend days this month so far.
  int get monthCount =>
      days.where((d) => today.yearMonth.contains(d.date) && d.isNoSpend).length;

  /// Whether this week has as many no-spend days as any earlier week that
  /// started this month, and at least one.
  bool get weekIsBestThisMonth {
    final count = weekCount;
    if (count == 0) return false;
    final start = weekStartOn(today, weekStartsOn);
    for (
      var w = start.addDays(-7);
      today.yearMonth.contains(w);
      w = w.addDays(-7)
    ) {
      final earlier = days.where(
        (d) => !d.date.isBefore(w) && d.date.isBefore(w.addDays(7)),
      );
      if (earlier.where((d) => d.isNoSpend).length > count) return false;
    }
    return true;
  }

  /// The latest no-spend day this week that had money out left out, to
  /// say why it still counts; null when there is none.
  DaySpend? get latestWithLeftOut {
    for (final d in week.reversed) {
      if (d.isNoSpend && d.leftOut.isNotEmpty) return d;
    }
    return null;
  }
}
