import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/insights/category_breakdown.dart';
import '../../../domain/insights/spending_charts.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/insights_providers.dart';
import '../application/month_labels.dart';

/// Colours for a category's subcategories, in order; the parent's own
/// spending is always the muted one.
List<Color> subcategorySeries(BuildContext context) {
  final colors = PesaColors.of(context);
  return [
    colors.markBlue,
    colors.markTeal,
    colors.markPurple,
    colors.warning,
    colors.success,
    colors.link,
  ];
}

/// Insights › a category with subcategories: what was spent on it in the
/// chart's period, against the period before, and how it splits by
/// subcategory. The ring keeps the category as one slice; tapping it opens
/// this.
class CategoryBreakdownScreen extends ConsumerWidget {
  const CategoryBreakdownScreen({required this.categoryId, super.key});

  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final period = ref.watch(chartPeriodProvider);
    final names = ref.watch(categoryNamesProvider).value ?? const {};
    final name = names[categoryId] ?? 'Category';
    final async = ref.watch(categoryBreakdownProvider((categoryId, period)));
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final appBar = AppBar(title: Text(name));
    final breakdown = async.value;
    if (breakdown == null) {
      return Scaffold(
        appBar: appBar,
        body: async.hasError
            ? ErrorView(
                '$name could not load.',
                onRetry: () => ref.invalidate(
                  categoryBreakdownProvider((categoryId, period)),
                ),
              )
            : const LoadingView(),
      );
    }

    final series = subcategorySeries(context);
    Color colorOf(int i, BreakdownRow row) => row.subcategoryId == null
        ? colors.textMuted
        : series[i % series.length];
    String rowName(BreakdownRow row) => row.subcategoryId == null
        ? '$name (no subcategory)'
        : names[row.subcategoryId] ?? 'Subcategory';
    void open(BreakdownRow row) {
      final window = breakdown.window;
      final last = window.end.addDays(-1);
      context.go(
        AppRoutes.activityWith(
          ActivityFilter(
            from: window.start,
            to: today.isBefore(last) ? today : last,
            categoryId: row.subcategoryId ?? categoryId,
          ),
        ),
      );
    }

    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    final change = breakdown.changeMinor;
    final before = _previousName(period, breakdown.window);
    final summary = [
      _count(breakdown.count),
      if (breakdown.previousMinor > 0 && change != 0)
        '${shownMoney(context, change.abs(), withCurrency: true)} '
            '${change < 0 ? 'less' : 'more'} than $before',
    ].join(' · ');

    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(_windowName(period, breakdown.window), style: muted),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spent on $name', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    shownMoney(
                      context,
                      breakdown.totalMinor,
                      withCurrency: true,
                    ),
                    key: const Key('breakdown-total'),
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  if (breakdown.totalMinor > 0) ...[
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, box) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          children: [
                            for (final (i, row) in breakdown.rows.indexed)
                              if (row.amountMinor > 0)
                                Container(
                                  width:
                                      box.maxWidth *
                                      row.amountMinor /
                                      breakdown.totalMinor,
                                  height: 8,
                                  color: colorOf(i, row),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (breakdown.rows.isNotEmpty) ...[
            const SectionLabel('By subcategory'),
            Card(
              child: Column(
                children: [
                  for (final (i, row) in breakdown.rows.indexed)
                    ListTile(
                      key: Key('breakdown-row-${row.subcategoryId ?? 'own'}'),
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorOf(i, row),
                          shape: BoxShape.circle,
                        ),
                      ),
                      minLeadingWidth: 8,
                      title: Text(rowName(row)),
                      subtitle: Text(
                        '${_count(row.count)} · '
                        '${breakdown.percentOf(row)}%',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shownMoney(
                              context,
                              row.amountMinor,
                              withCurrency: true,
                            ),
                            style: theme.textTheme.titleSmall,
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: colors.textMuted,
                          ),
                        ],
                      ),
                      onTap: () => open(row),
                    ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Nothing spent on $name yet.', style: muted),
            ),
        ],
      ),
    );
  }
}

String _count(int n) => n == 1 ? '1 transaction' : '$n transactions';

String _windowName(ChartPeriod period, ChartWindow window) => switch (period) {
  ChartPeriod.week =>
    'Week from ${window.start.day} '
        '${monthName(window.start.yearMonth)}',
  ChartPeriod.month =>
    '${monthName(window.start.yearMonth)} ${window.start.year}',
  ChartPeriod.year => '${window.start.year}',
};

String _previousName(ChartPeriod period, ChartWindow window) =>
    switch (period) {
      ChartPeriod.week => 'last week',
      ChartPeriod.month => monthName(window.start.yearMonth.previous),
      ChartPeriod.year => '${window.start.year - 1}',
    };
