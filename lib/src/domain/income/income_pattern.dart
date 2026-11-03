import 'dart:math';

import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';

/// How far back the pattern looks.
const incomePatternDays = 180;

/// The fewest arrivals that can show a rhythm.
const incomePatternMinArrivals = 3;

/// Gaps shorter than this are "most days", not a rhythm to plan around.
const incomePatternMinGapDays = 5;

/// How the money that arrives has behaved: how often, how steadily and from
/// how many people. Learnt on the phone from the ledger.
class IncomePattern {
  const IncomePattern({
    required this.arrivalDays,
    required this.senders,
    this.lastArrival,
    this.typicalGapDays,
    this.steady = false,
  });

  /// Reads the pattern from [history] up to [today]. Money in counts when
  /// it is income or from someone not named yet; borrowing, reversals and
  /// own transfers never count.
  factory IncomePattern.of(
    Iterable<LedgerEntry> history, {
    required CalendarDate today,
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    final from = today.addDays(-incomePatternDays);
    final days = <CalendarDate>{};
    final senders = <String>{};
    for (final e in history) {
      if (e.currency != currency || !e.isInflow || e.amountMinor <= 0) continue;
      final role = roleOf(e);
      if (role != LedgerRole.income && role != LedgerRole.awaitingPayee) {
        continue;
      }
      final date = e.date;
      if (date.isBefore(from) || date.isAfter(today)) continue;
      days.add(date);
      final who = e.payeeId?.toString() ?? e.counterpartyValue;
      if (who != null) senders.add(who);
    }
    final sorted = days.toList()..sort((a, b) => a.compareTo(b));
    if (sorted.isEmpty) {
      return IncomePattern(arrivalDays: 0, senders: senders.length);
    }
    final gaps = [
      for (var i = 1; i < sorted.length; i++)
        sorted[i - 1].daysUntil(sorted[i]),
    ];
    int? typical;
    var steady = false;
    if (sorted.length >= incomePatternMinArrivals) {
      typical = _median(gaps);
      final spread = _median([for (final g in gaps) (g - typical).abs()]);
      steady =
          typical >= incomePatternMinGapDays && spread <= max(2, typical ~/ 4);
    }
    return IncomePattern(
      arrivalDays: sorted.length,
      senders: senders.length,
      lastArrival: sorted.last,
      typicalGapDays: typical,
      steady: steady,
    );
  }

  /// Days on which money arrived.
  final int arrivalDays;

  /// Different people or tills it came from.
  final int senders;
  final CalendarDate? lastArrival;

  /// The usual number of days between arrivals.
  final int? typicalGapDays;

  /// Whether arrivals keep a rhythm worth planning around.
  final bool steady;

  /// When money is next likely, for a steady rhythm; null otherwise. A
  /// rhythm that is overdue expects it tomorrow.
  CalendarDate? nextExpected(CalendarDate today) {
    final last = lastArrival;
    final gap = typicalGapDays;
    if (!steady || last == null || gap == null) return null;
    final next = last.addDays(gap);
    return next.isAfter(today) ? next : today.addDays(1);
  }
}

int _median(List<int> values) {
  final s = [...values]..sort();
  return s[s.length ~/ 2];
}
