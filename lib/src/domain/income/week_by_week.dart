import '../ledger/ledger_entry.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';

/// Complete weeks before this one that set what a usual week is.
const usualWeeksCount = 8;

/// Weeks the chart shows, this one included.
const weeksShown = 5;

/// The share of a good week's extra money suggested for the fund, in
/// percent.
const rainyDaySharePercent = 50;

/// Suggested rainy day fund amounts are rounded down to this many minor units.
const rainyDayStepMinor = 10000;

/// The Monday that starts [date]'s week.
CalendarDate weekStartOf(CalendarDate date) => date.addDays(1 - date.weekday);

/// Money in and out for one week, Monday to Sunday.
class WeekFlow {
  const WeekFlow({
    required this.start,
    required this.inMinor,
    required this.outMinor,
  });

  final CalendarDate start;

  /// Income, and money from people not named yet.
  final int inMinor;

  /// Spending, fees, tax and debt payments. Savings and own transfers stay
  /// out.
  final int outMinor;

  CalendarDate get end => start.addDays(6);
}

/// Money set aside in good weeks for lean ones. It stays in the person's
/// accounts; the app keeps it out of what is safe to spend.
class RainyDayFund {
  const RainyDayFund([this.moves = const []]);

  /// Adds (positive) and takes (negative), oldest first.
  final List<RainyDayMove> moves;

  int get balanceMinor {
    final total = moves.fold(0, (sum, m) => sum + m.amountMinor);
    return total < 0 ? 0 : total;
  }

  /// Whether anything went in during the week starting [weekStart].
  bool addedInWeek(CalendarDate weekStart) => moves.any(
    (m) =>
        m.amountMinor > 0 &&
        !m.on.isBefore(weekStart) &&
        !m.on.isAfter(weekStart.addDays(6)),
  );

  RainyDayFund withMove(RainyDayMove move) => RainyDayFund([...moves, move]);

  static RainyDayFund fromJson(Map<String, Object?>? json) {
    final raw = json?['moves'];
    if (raw is! List) return const RainyDayFund();
    final moves = <RainyDayMove>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final on = m['on'];
      final amount = m['amountMinor'];
      if (on is! String || amount is! int) continue;
      final parts = on.split('-').map(int.tryParse).toList();
      if (parts.length != 3 || parts.contains(null)) continue;
      moves.add(
        RainyDayMove(
          on: CalendarDate(parts[0]!, parts[1]!, parts[2]!),
          amountMinor: amount,
        ),
      );
    }
    return RainyDayFund(moves);
  }

  Map<String, Object?> toJson() => {
    'moves': [
      for (final m in moves)
        {'on': m.on.toString(), 'amountMinor': m.amountMinor},
    ],
  };
}

class RainyDayMove {
  const RainyDayMove({required this.on, required this.amountMinor});

  final CalendarDate on;
  final int amountMinor;
}

/// The week-by-week plan for business and gigs: this week against a usual
/// one, and what to put in or take from the fund.
class WeekByWeek {
  const WeekByWeek({
    required this.weeks,
    required this.usualInMinor,
    required this.usualOutMinor,
    required this.fund,
    required this.today,
  });

  /// Weeks from [history], oldest first; the last is this week so far.
  factory WeekByWeek.of(
    Iterable<LedgerEntry> history, {
    required CalendarDate today,
    RainyDayFund fund = const RainyDayFund(),
  }) {
    final thisWeek = weekStartOf(today);
    final weeks = <WeekFlow>[];
    for (var i = usualWeeksCount; i >= 0; i--) {
      final start = thisWeek.addDays(-7 * i);
      final totals = LedgerTotals.of(
        history,
        from: start.startInstant,
        to: start.addDays(7).startInstant,
      );
      weeks.add(
        WeekFlow(
          start: start,
          inMinor: totals.incomeMinor + totals.awaitingPayeeMinor,
          outMinor:
              totals.spendingMinor +
              totals.feesMinor +
              totals.taxMinor +
              totals.debtRepaymentMinor,
        ),
      );
    }
    final past = weeks.sublist(0, weeks.length - 1);
    return WeekByWeek(
      weeks: weeks,
      usualInMinor: _median([for (final w in past) w.inMinor]),
      usualOutMinor: _median([for (final w in past) w.outMinor]),
      fund: fund,
      today: today,
    );
  }

  final List<WeekFlow> weeks;
  final int usualInMinor;
  final int usualOutMinor;
  final RainyDayFund fund;
  final CalendarDate today;

  WeekFlow get thisWeek => weeks.last;

  /// The weeks the chart shows, oldest first.
  List<WeekFlow> get shown => weeks.sublist(weeks.length - weeksShown);

  /// The rainy day fund aims at one usual week's spending, enough to cover a week
  /// when little comes in.
  int get targetMinor => usualOutMinor;

  /// This week's money in above a usual week.
  int get extraMinor {
    final extra = thisWeek.inMinor - usualInMinor;
    return extra < 0 ? 0 : extra;
  }

  /// What to put in the rainy day fund this week: a share of the extra, up to the
  /// target, once a week.
  int get suggestAddMinor {
    if (fund.addedInWeek(thisWeek.start)) return 0;
    final room = targetMinor - fund.balanceMinor;
    if (room <= 0) return 0;
    var share = extraMinor * rainyDaySharePercent ~/ 100;
    if (share > room) share = room;
    return share ~/ rainyDayStepMinor * rainyDayStepMinor;
  }

  /// What may come out of the rainy day fund in a lean week: what this week's money
  /// in falls short of usual spending, up to what is there.
  int get suggestTakeMinor {
    final week = thisWeek;
    if (week.inMinor >= usualInMinor || week.outMinor <= week.inMinor) {
      return 0;
    }
    var need = usualOutMinor - week.inMinor;
    if (need > fund.balanceMinor) need = fund.balanceMinor;
    return need < 0 ? 0 : need;
  }
}

int _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) ~/ 2;
}
