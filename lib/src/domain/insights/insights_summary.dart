import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';
import 'leakage.dart';

/// One month's figures for Insights.
class MonthInsight {
  const MonthInsight({
    required this.month,
    required this.totals,
    required this.leakage,
    required this.entryCount,
  });

  final YearMonth month;
  final LedgerTotals totals;
  final LeakageBreakdown leakage;
  final int entryCount;

  int get incomeMinor => totals.incomeMinor;

  /// Spending plus fees, as the Financial Health Index counts it.
  int get spendingMinor => totals.spendingMinor + totals.feesMinor;

  int get leakageMinor => leakage.totalMinor;

  /// Leakage as a share of income, or null with no income.
  int? get leakageShareBasisPoints =>
      shareBasisPoints(leakageMinor, incomeMinor);
}

/// What Insights shows for [month]: its leakages, the change on the month
/// before, and spending over the last [trendMonths] months.
class InsightsSummary {
  const InsightsSummary({required this.trend});

  /// Works out [month] and the months before it from [history], which should
  /// start a month before the earliest trend month so Fuliza repayments find
  /// their draws.
  factory InsightsSummary.of(
    Iterable<LedgerEntry> history, {
    required YearMonth month,
    int trendMonths = 6,
    String currency = 'KES',
  }) {
    final all = history.where((e) => e.currency == currency).toList();
    final fuliza = FulizaLedger.of(all);
    final first = month.addMonths(1 - trendMonths);
    return InsightsSummary(
      trend: [
        for (var i = 0; i < trendMonths; i++)
          _monthOf(all, first.addMonths(i), fuliza, currency),
      ],
    );
  }

  /// Oldest first; the last is the month shown.
  final List<MonthInsight> trend;

  MonthInsight get current => trend.last;

  MonthInsight? get previous =>
      trend.length < 2 ? null : trend[trend.length - 2];

  /// Leakage this month less last month's.
  int get leakageChangeMinor =>
      current.leakageMinor - (previous?.leakageMinor ?? 0);

  /// Half this month's leakage, rounded down to the nearest 100 shillings.
  int get halfLeakageMinor => current.leakageMinor ~/ 2 ~/ 10000 * 10000;

  /// Whether any month in the trend has transactions.
  bool get hasData => trend.any((m) => m.entryCount > 0);
}

MonthInsight _monthOf(
  List<LedgerEntry> all,
  YearMonth month,
  FulizaLedger fuliza,
  String currency,
) {
  final from = month.startInstant;
  final to = month.endInstant;
  var count = 0;
  for (final e in all) {
    if (!e.occurredAt.isBefore(from) && e.occurredAt.isBefore(to)) count++;
  }
  return MonthInsight(
    month: month,
    totals: LedgerTotals.of(all, from: from, to: to, currency: currency),
    leakage: LeakageBreakdown.of(
      all,
      from: from,
      to: to,
      currency: currency,
      fuliza: fuliza,
    ),
    entryCount: count,
  );
}
