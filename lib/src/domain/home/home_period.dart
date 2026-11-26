import '../../core/money/money.dart';
import '../books/journal_balances.dart';
import '../ledger/activity_feed.dart';
import '../ledger/activity_lines.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';
import '../time/week_start.dart';

/// Home's tabs: the stretch of time its figures and days cover.
enum HomePeriod {
  thisWeek('This week'),
  lastWeek('Last week'),
  thisMonth('This month'),
  lastMonth('Last month');

  const HomePeriod(this.label);

  final String label;

  /// The days this period covers on [today], both ends included: this
  /// week and this month run to today; last week and last month are whole.
  /// Weeks start on [weekStartsOn] (see [FirstWeekday]).
  DateSpan spanOn(CalendarDate today, {int? weekStartsOn}) {
    final week = weekStartOn(today, weekStartsOn);
    return switch (this) {
      thisWeek => DateSpan(week, today),
      lastWeek => DateSpan(week.addDays(-7), week.addDays(-1)),
      thisMonth => DateSpan(today.yearMonth.firstDay, today),
      lastMonth => DateSpan(
        today.yearMonth.previous.firstDay,
        today.yearMonth.previous.lastDay,
      ),
    };
  }
}

/// Days from [first] to [last], both included.
class DateSpan {
  const DateSpan(this.first, this.last);

  final CalendarDate first;
  final CalendarDate last;

  bool contains(CalendarDate date) =>
      !date.isBefore(first) && !date.isAfter(last);

  @override
  bool operator ==(Object other) =>
      other is DateSpan && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

/// Money in and out for a stretch of days, from the shared money rules
/// ([LedgerTotals]): own transfers, borrowing and corrections are neither
/// in nor out. Money out is spending and fees, as Activity's week counts
/// it; [feesMinor] is the part of it that was fees.
class InOut {
  const InOut({this.inMinor = 0, this.outMinor = 0, this.feesMinor = 0});

  /// Totals for [span] from [history], which should reach back before it
  /// so Fuliza repayments find their draws.
  factory InOut.of(
    Iterable<LedgerEntry> history,
    DateSpan span, {
    String? currency,
    JournalBalances? journal,
  }) {
    final totals = LedgerTotals.of(
      history,
      from: span.first.startInstant,
      to: span.last.addDays(1).startInstant,
      currency: currency ?? BaseCurrency.code,
      journal: journal,
    );
    return InOut(
      inMinor: totals.moneyInMinor,
      outMinor: totals.spendingMinor + totals.feesMinor,
      feesMinor: totals.feesMinor,
    );
  }

  /// Money in ([LedgerTotals.moneyInMinor]).
  final int inMinor;
  final int outMinor;
  final int feesMinor;

  /// In less out; below zero when more went out.
  int get differenceMinor => inMinor - outMinor;
}

/// One day on Home: its lines as Activity shows them, newest first, and
/// the day's money in and out.
class HomeDay {
  const HomeDay({required this.date, required this.lines, required this.sums});

  final CalendarDate date;
  final List<ActivityLine> lines;
  final InOut sums;
}

/// Days Home shows under the figures; the rest are in Activity.
const homeDaysShown = 3;

/// What Home shows for one tab: the period's money in and out and its last
/// [homeDaysShown] days with records, newest first.
class HomePeriodView {
  const HomePeriodView({
    required this.period,
    required this.span,
    required this.sums,
    required this.days,
    required this.hasRecords,
    this.payday,
  });

  /// Works out [period] on [today] from [history], which reaches back
  /// before the period's first day. Only entries [listed] allows show in
  /// the days (Fuliza's are left out while it is not tracked); every entry
  /// counts in the totals.
  factory HomePeriodView.of(
    Iterable<LedgerEntry> history, {
    required HomePeriod period,
    required CalendarDate today,
    int? weekStartsOn,
    JournalBalances? journal,
    String? currency,
    bool Function(LedgerEntry)? listed,
    bool? anyRecords,
    CalendarDate? payday,
  }) {
    // Since payday: from the payday itself, its money in included, to today.
    final span = payday != null && !payday.isAfter(today)
        ? DateSpan(payday, today)
        : period.spanOn(today, weekStartsOn: weekStartsOn);
    final all = history.toList();
    final inSpan = [
      for (final e in all)
        if (span.contains(e.date) && (listed == null || listed(e))) e,
    ];
    final feed = buildActivityFeed(inSpan, all: all);
    return HomePeriodView(
      period: period,
      span: span,
      sums: InOut.of(all, span, currency: currency, journal: journal),
      days: [
        for (final day in feed.take(homeDaysShown))
          HomeDay(
            date: day.date,
            lines: day.lines,
            sums: InOut.of(
              all,
              DateSpan(day.date, day.date),
              currency: currency,
              journal: journal,
            ),
          ),
      ],
      hasRecords: anyRecords ?? all.isNotEmpty,
      payday: payday != null && !payday.isAfter(today) ? payday : null,
    );
  }

  final HomePeriod period;
  final DateSpan span;

  /// The last payday when [span] runs from it rather than [period]'s days.
  final CalendarDate? payday;

  /// Whether [span] runs since the last payday.
  bool get sincePayday => payday != null;
  final InOut sums;

  /// Newest first, at most [homeDaysShown].
  final List<HomeDay> days;

  /// Whether the space has any records at all, in this period or before
  /// ([anyRecords] when the caller knows; otherwise whether [history] has
  /// any).
  final bool hasRecords;
}
