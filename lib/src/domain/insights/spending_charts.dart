import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';

/// The stretch of time a chart covers.
enum ChartPeriod { week, month, year }

/// Days `[start, end)`.
class ChartWindow {
  const ChartWindow(this.start, this.end);

  /// The [period] holding [today]; weeks start on Monday.
  factory ChartWindow.of(ChartPeriod period, CalendarDate today) =>
      switch (period) {
        ChartPeriod.week => ChartWindow(
          today.addDays(1 - today.weekday),
          today.addDays(8 - today.weekday),
        ),
        ChartPeriod.month => ChartWindow(
          today.yearMonth.firstDay,
          today.yearMonth.next.firstDay,
        ),
        ChartPeriod.year => ChartWindow(
          CalendarDate(today.year, 1, 1),
          CalendarDate(today.year + 1, 1, 1),
        ),
      };

  final CalendarDate start;
  final CalendarDate end;

  int get days => start.daysUntil(end);

  /// The window of the same [period] just before this one.
  ChartWindow previous(ChartPeriod period) => switch (period) {
    ChartPeriod.week => ChartWindow(start.addDays(-7), start),
    ChartPeriod.month => ChartWindow(start.yearMonth.previous.firstDay, start),
    ChartPeriod.year => ChartWindow(CalendarDate(start.year - 1, 1, 1), start),
  };

  bool contains(CalendarDate date) =>
      !date.isBefore(start) && date.isBefore(end);
}

/// What one slice of the spending chart stands for.
sealed class SliceKey {
  const SliceKey();
}

final class CategorySlice extends SliceKey {
  const CategorySlice(this.categoryId);

  final int categoryId;

  @override
  bool operator ==(Object other) =>
      other is CategorySlice && other.categoryId == categoryId;

  @override
  int get hashCode => categoryId.hashCode;
}

/// Transaction costs and charges.
final class FeesSlice extends SliceKey {
  const FeesSlice();
}

/// Spending with no category yet.
final class UncategorisedSlice extends SliceKey {
  const UncategorisedSlice();
}

/// The smaller slices, put together.
final class OtherSlice extends SliceKey {
  const OtherSlice();
}

typedef Slice = ({SliceKey key, int amountMinor});

/// Spending in a window by category, and day by day against the window
/// before it.
class SpendingChart {
  const SpendingChart({
    required this.window,
    required this.slices,
    required this.cumulative,
    required this.previousCumulative,
  });

  /// Charts [period] around [today] from [history], which should reach back
  /// to the start of the previous window and a month before it, so Fuliza
  /// repayments find their draws. At most [maxSlices] slices; the rest are
  /// put together as [OtherSlice].
  factory SpendingChart.of(
    Iterable<LedgerEntry> history, {
    required ChartPeriod period,
    required CalendarDate today,
    String currency = 'KES',
    int maxSlices = 6,
  }) {
    final all = history.where((e) => e.currency == currency).toList();
    final fuliza = FulizaLedger.of(all);
    final window = ChartWindow.of(period, today);
    final before = window.previous(period);

    final byKey = <SliceKey, int>{};
    final daily = List.filled(window.days, 0);
    final previousDaily = List.filled(before.days, 0);
    for (final entry in all) {
      final date = entry.date;
      final inWindow = window.contains(date);
      if (!inWindow && !before.contains(date)) continue;
      final parts = _spendingOf(entry, fuliza);
      if (parts.isEmpty) continue;
      if (inWindow) {
        final day = window.start.daysUntil(date);
        for (final (key, amount) in parts) {
          byKey[key] = (byKey[key] ?? 0) + amount;
          daily[day] += amount;
        }
      } else {
        final day = before.start.daysUntil(date);
        for (final (_, amount) in parts) {
          previousDaily[day] += amount;
        }
      }
    }

    final ranked = [
      for (final MapEntry(:key, :value) in byKey.entries)
        if (value > 0) (key: key, amountMinor: value),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final slices = ranked.length <= maxSlices
        ? ranked
        : [
            ...ranked.take(maxSlices - 1),
            (
              key: const OtherSlice(),
              amountMinor: ranked
                  .skip(maxSlices - 1)
                  .fold(0, (sum, s) => sum + s.amountMinor),
            ),
          ];

    final shown = today.isBefore(window.end)
        ? window.start.daysUntil(today) + 1
        : window.days;
    return SpendingChart(
      window: window,
      slices: slices,
      cumulative: _runningTotal(daily.take(shown)),
      previousCumulative: _runningTotal(previousDaily),
    );
  }

  final ChartWindow window;

  /// Largest first.
  final List<Slice> slices;

  /// Spending to the end of each day of the window, up to today.
  final List<int> cumulative;

  /// The same for each day of the window before.
  final List<int> previousCumulative;

  int get totalMinor => slices.fold(0, (sum, s) => sum + s.amountMinor);

  /// Spent so far less what was spent by the same day of the window before;
  /// negative when spending is lower. Null with nothing to compare.
  int? get changeToDateMinor {
    if (cumulative.isEmpty || previousCumulative.isEmpty) return null;
    final day = cumulative.length < previousCumulative.length
        ? cumulative.length
        : previousCumulative.length;
    return cumulative.last - previousCumulative[day - 1];
  }

  bool get hasData =>
      slices.isNotEmpty || previousCumulative.any((total) => total != 0);
}

/// The spending in [entry], split into fees and the rest, as Insights counts
/// it: spending net of refunds, plus every fee.
List<(SliceKey, int)> _spendingOf(LedgerEntry entry, FulizaLedger fuliza) {
  final parts = <(SliceKey, int)>[];
  if (entry.feeMinor > 0) parts.add((const FeesSlice(), entry.feeMinor));
  final category = entry.categoryId == null
      ? const UncategorisedSlice()
      : CategorySlice(entry.categoryId!);
  switch (roleOf(entry)) {
    case LedgerRole.spending:
      parts.add((category, entry.amountMinor));
    case LedgerRole.fee:
      parts.add((const FeesSlice(), entry.amountMinor));
    case LedgerRole.debtRepayment:
      final fee = fuliza.feeOf(entry);
      if (fee > 0) parts.add((const FeesSlice(), fee));
    case LedgerRole.reversal when entry.isInflow:
      parts.add((category, -entry.amountMinor));
    case _:
      break;
  }
  return parts;
}

List<int> _runningTotal(Iterable<int> daily) {
  var total = 0;
  return [for (final amount in daily) total += amount];
}
