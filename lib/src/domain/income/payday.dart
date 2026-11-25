import '../../core/money/money.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';
import 'income_pattern.dart';

/// The shortest rhythm that counts as a payday: weekly or slower.
const paydayMinGapDays = 7;

/// The main regular money in: the sender whose arrivals keep a steady
/// rhythm (see [IncomePattern]) and who paid the most over the last
/// [incomePatternDays]. Null for irregular earners and new users, and once
/// a payday is well overdue.
class Payday {
  const Payday({required this.last, required this.gapDays});

  /// Finds the main payday in [history] up to [today]. Money in counts as
  /// [IncomePattern] counts it, grouped by who sent it.
  static Payday? of(
    Iterable<LedgerEntry> history, {
    required CalendarDate today,
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    final from = today.addDays(-incomePatternDays);
    final bySender = <String, List<LedgerEntry>>{};
    for (final e in history) {
      if (e.currency != currency || e.amountMinor <= 0) continue;
      if (!isMoneyArrived(e)) continue;
      if (e.date.isBefore(from) || e.date.isAfter(today)) continue;
      final who = _sender(e);
      if (who == null) continue;
      (bySender[who] ??= []).add(e);
    }
    Payday? best;
    var bestTotal = 0;
    for (final entries in bySender.values) {
      final pattern = IncomePattern.of(
        entries,
        today: today,
        currency: currency,
      );
      final gap = pattern.typicalGapDays;
      final last = pattern.lastArrival;
      if (!pattern.steady || gap == null || last == null) continue;
      if (gap < paydayMinGapDays) continue;
      // A payday missed by half a cycle is no longer a rhythm to go by.
      if (last.addDays(gap + gap ~/ 2).isBefore(today)) continue;
      final total = entries.fold(0, (sum, e) => sum + e.amountMinor);
      if (best == null || total > bestTotal) {
        best = Payday(last: last, gapDays: gap);
        bestTotal = total;
      }
    }
    return best;
  }

  /// The day the main money last came in.
  final CalendarDate last;

  /// The usual days between paydays.
  final int gapDays;

  /// When it is next expected: tomorrow once overdue, as
  /// [IncomePattern.nextExpected].
  CalendarDate nextAfter(CalendarDate today) {
    final next = last.addDays(gapDays);
    return next.isAfter(today) ? next : today.addDays(1);
  }
}

String? _sender(LedgerEntry e) =>
    e.payeeId?.toString() ??
    e.counterpartyValue ??
    e.counterpartyName ??
    e.payeeName;
