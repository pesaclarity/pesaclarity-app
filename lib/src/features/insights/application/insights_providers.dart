import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/tags_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/insights/first_insight.dart';
import '../../../domain/insights/insights_summary.dart';
import '../../../domain/insights/spending_charts.dart';
import '../../../domain/time/calendar.dart';

/// How far back the first scan reads, and so the first insight covers.
const firstInsightDays = 90;

/// This Nairobi month's leakages, its change on last month, and the
/// six-month spending trend.
final insightsSummaryProvider = FutureProvider<InsightsSummary>((ref) async {
  final month = CalendarDate.nairobi(ref.watch(clockProvider)()).yearMonth;
  // A month before the trend's first month lets Fuliza repayments find their
  // draws.
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: month.addMonths(-6).startInstant,
        to: month.endInstant,
      );
  return InsightsSummary.of(entries, month: month);
});

/// Tag names by id.
final tagNamesProvider = StreamProvider<Map<int, String>>(
  (ref) => ref
      .watch(tagsRepositoryProvider)
      .watchAll()
      .map((tags) => {for (final t in tags) t.id: t.name}),
);

/// Income, spending, leakages and Fuliza fees over the days the first scan
/// read, up to the end of today.
final firstInsightProvider = FutureProvider<FirstInsight>((ref) async {
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final from = today.addDays(-firstInsightDays).startInstant;
  final to = today.addDays(1).startInstant;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: to);
  return FirstInsight.of(entries, from: from, to: to);
});

/// The period the spending charts show.
class ChartPeriodController extends Notifier<ChartPeriod> {
  @override
  ChartPeriod build() => ChartPeriod.month;

  void select(ChartPeriod period) => state = period;
}

final chartPeriodProvider =
    NotifierProvider<ChartPeriodController, ChartPeriod>(
      ChartPeriodController.new,
    );

/// Spending by category in the chosen period, and day by day against the
/// period before. Updates as the ledger changes.
final spendingChartProvider = FutureProvider<SpendingChart>((ref) async {
  ref.watch(ledgerChangesProvider);
  final period = ref.watch(chartPeriodProvider);
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final window = ChartWindow.of(period, today);
  // A month before the previous window lets Fuliza repayments find draws.
  final from = window.previous(period).start.yearMonth.previous.startInstant;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: window.end.startInstant);
  return SpendingChart.of(entries, period: period, today: today);
});

/// Category names by id.
final categoryNamesProvider = StreamProvider<Map<int, String>>(
  (ref) => ref
      .watch(categoriesRepositoryProvider)
      .watchAll()
      .map((all) => {for (final c in all) c.id: c.name}),
);
