import '../enums.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';
import 'leakage.dart';

/// What the first scan found, shown before Home: income, spending, leakages
/// and Fuliza (overdraft) fees over the scanned period.
class FirstInsight {
  const FirstInsight({
    required this.from,
    required this.to,
    required this.transactionCount,
    required this.totals,
    required this.leakage,
    required this.fulizaDays,
  });

  /// Works out the insight for entries in [currency] whose time is in
  /// `[from, to)`. One pass for the totals, one for the leakages, and one
  /// over Fuliza entries only, so a few thousand rows take milliseconds.
  factory FirstInsight.of(
    Iterable<LedgerEntry> entries, {
    required DateTime from,
    required DateTime to,
    String currency = 'KES',
  }) {
    final all = entries.where((e) => e.currency == currency).toList();
    final fuliza = FulizaLedger.of(all);
    var count = 0;
    final drawDays = <CalendarDate>{};
    for (final e in all) {
      if (e.occurredAt.isBefore(from) || !e.occurredAt.isBefore(to)) continue;
      count++;
      if (e.kind == TransactionKind.fulizaDraw) drawDays.add(e.date);
    }
    return FirstInsight(
      from: from,
      to: to,
      transactionCount: count,
      totals: LedgerTotals.of(all, from: from, to: to, currency: currency),
      leakage: LeakageBreakdown.of(
        all,
        from: from,
        to: to,
        currency: currency,
        fuliza: fuliza,
      ),
      fulizaDays: drawDays.length,
    );
  }

  final DateTime from;
  final DateTime to;
  final int transactionCount;
  final LedgerTotals totals;
  final LeakageBreakdown leakage;

  /// Days with at least one Fuliza draw.
  final int fulizaDays;

  int get incomeMinor => totals.incomeMinor;

  /// Spending plus fees.
  int get spendingMinor => totals.spendingMinor + totals.feesMinor;

  int get leakageMinor => leakage.totalMinor;

  int get fulizaFeesMinor => leakage.fulizaMinor;

  /// Leakage as a share of income, or null with no income.
  int? get leakageShareBasisPoints =>
      shareBasisPoints(leakageMinor, incomeMinor);
}
