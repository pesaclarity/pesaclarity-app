import '../enums.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';

/// One month of Fuliza use, with the days spent overdrawn.
class FulizaTrackerMonth {
  const FulizaTrackerMonth({
    required this.usage,
    required this.daysOverdrawn,
    required this.isClimbing,
  });

  /// Draws, repayments and fees, from [FulizaLedger].
  final FulizaMonth usage;

  /// Nairobi days on which some Fuliza was owed, even for an hour.
  final int daysOverdrawn;

  /// Used more than the month before: more days overdrawn and more drawn.
  /// The cue for a gentle nudge.
  final bool isClimbing;

  YearMonth get month => usage.month;
}

/// Fuliza draws, fees and days overdrawn per month, from the ledger.
class FulizaTracker {
  FulizaTracker._(this._entries, this._ledger, this._overdrawnDays);

  /// Reads Fuliza draws and repayments from [entries]; anything else is
  /// ignored. Fuliza still owed after the last entry counts as owed up to
  /// [asOf] (the last entry's day when not given).
  factory FulizaTracker.of(
    Iterable<LedgerEntry> entries, {
    CalendarDate? asOf,
  }) {
    final fuliza =
        entries
            .where(
              (e) =>
                  e.kind == TransactionKind.fulizaDraw ||
                  e.kind == TransactionKind.fulizaRepayment,
            )
            .toList()
          ..sort(compareFulizaEntries);

    final days = <CalendarDate>{};
    var outstanding = 0;
    CalendarDate? owedSince;
    for (final entry in fuliza) {
      final day = entry.date;
      if (entry.kind == TransactionKind.fulizaDraw) {
        outstanding += entry.amountMinor;
        owedSince ??= day;
      } else {
        outstanding -= outstanding < entry.amountMinor
            ? outstanding
            : entry.amountMinor;
        if (outstanding == 0 && owedSince != null) {
          _addDays(days, owedSince, day);
          owedSince = null;
        }
      }
    }
    if (owedSince != null) {
      final end = asOf ?? fuliza.last.date;
      _addDays(days, owedSince, end.isBefore(owedSince) ? owedSince : end);
    }

    return FulizaTracker._(fuliza, FulizaLedger.of(fuliza), days);
  }

  final List<LedgerEntry> _entries;
  final FulizaLedger _ledger;
  final Set<CalendarDate> _overdrawnDays;

  /// Draws not yet repaid at the end of the entries.
  int get outstandingMinor => _ledger.outstandingMinor;

  int daysOverdrawnIn(YearMonth month) =>
      _overdrawnDays.where(month.contains).length;

  FulizaTrackerMonth month(YearMonth month) {
    final usage = _ledger.month(_entries, month);
    final days = daysOverdrawnIn(month);
    final previous = _ledger.month(_entries, month.previous);
    return FulizaTrackerMonth(
      usage: usage,
      daysOverdrawn: days,
      isClimbing:
          days > daysOverdrawnIn(month.previous) &&
          usage.drawsMinor > previous.drawsMinor,
    );
  }

  /// Every month from [from] to [to], inclusive, oldest first.
  List<FulizaTrackerMonth> months(YearMonth from, YearMonth to) => [
    for (var m = from; m.compareTo(to) <= 0; m = m.next) month(m),
  ];
}

void _addDays(Set<CalendarDate> days, CalendarDate from, CalendarDate to) {
  for (var d = from; !d.isAfter(to); d = d.addDays(1)) {
    days.add(d);
  }
}
