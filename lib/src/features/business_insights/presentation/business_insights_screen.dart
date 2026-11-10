import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../tax/application/tax_providers.dart';
import '../application/business_report_providers.dart';

/// The period the business's Insights shows, kept while the app is open so
/// Full records and Make a report start from it.
final insightsRangeProvider =
    NotifierProvider<InsightsRangeController, ReportRange>(
      InsightsRangeController.new,
    );

class InsightsRangeController extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.thisMonth;

  void set(ReportRange range) => state = range;
}

/// A business's Insights: how it is doing this month, last month or over
/// 3 months, with Full records at the top.
class BusinessInsightsScreen extends ConsumerWidget {
  const BusinessInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(insightsRangeProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final period = periodFor(range, today);
    final loaded = ref.watch(businessReportProvider(period));
    final report = loaded.value;
    final hidden = AmountsHidden.of(context);
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            TabHeader(
              'Insights',
              semanticsId: SemanticIds.titleBusinessInsights,
              actions: [
                PillButton(
                  key: const Key('insights-full-records'),
                  label: 'Full records',
                  onPressed: () => context.push(AppRoutes.fullRecords),
                ),
                const AmountsEye(),
              ],
            ),
            RangeMenu(
              selected: range,
              onSelected: (r) =>
                  ref.read(insightsRangeProvider.notifier).set(r),
            ),
            const SizedBox(height: 16),
            if (report == null && loaded.hasError)
              ErrorView(
                'Your figures could not load.',
                onRetry: () => ref.invalidate(businessReportProvider(period)),
              )
            else if (report == null)
              const LoadingView(inList: true)
            else ...[
              _ProfitCard(report, range: range, plain: plain),
              if (report.byWay.isNotEmpty) ...[
                const SizedBox(height: 12),
                _HowPeoplePay(report, plain: plain),
              ],
              if (report.bestSellers.isNotEmpty) ...[
                const SizedBox(height: 12),
                _BestSellers(report, plain: plain),
              ],
              if (report.byWeekday.any((v) => v > 0)) ...[
                const SizedBox(height: 12),
                _SalesByDay(report.byWeekday),
              ],
              // A best day or a share of sales means little from a few
              // days, so the sentences wait for two weeks of sales.
              if (_salesDays(report) < _sentencesAfterDays)
                const EmptyNote('Insights show after two weeks of sales.')
              else if (report.insights.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Sentences(report.insights),
              ],
              const SizedBox(height: 12),
              const _TaxCard(),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('insights-share-report'),
                onPressed: () => context.push(AppRoutes.makeReport),
                child: const Text('Share a report (PDF)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Days of sales in a period before Insights says anything about them,
/// such as the best day.
const _sentencesAfterDays = 14;

/// The days in [report]'s period that have sales.
int _salesDays(BusinessReport report) =>
    report.byDay.where((sold) => sold > 0).length;

/// This month, Last month and 3 months, and Choose dates with [onCustom], as
/// a drop-down keyed `range`. Its rows are keyed `range-<name>` and
/// `range-dates`.
class RangeMenu extends StatelessWidget {
  const RangeMenu({
    required this.selected,
    required this.onSelected,
    this.custom = false,
    this.onCustom,
    super.key,
  });

  final ReportRange? selected;
  final ValueChanged<ReportRange> onSelected;

  /// Whether "Choose dates" is the one chosen.
  final bool custom;

  /// Opens the dates to choose, each time "Choose dates" is chosen.
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ChoiceMenu<ReportRange?>(
      key: const Key('range'),
      name: 'Period',
      options: [
        for (final r in ReportRange.values) (r, r.label),
        if (onCustom != null) (null, 'Choose dates'),
      ],
      value: custom ? null : selected,
      itemKey: (r) => Key('range-${r?.name ?? 'dates'}'),
      onChanged: (r) => r == null ? onCustom?.call() : onSelected(r),
    ),
  );
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard(this.report, {required this.range, required this.plain});

  final BusinessReport report;
  final ReportRange range;
  final String Function(int minor) plain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final pnl = report.pnl;
    final profit = pnl.profitMinor;
    final before = report.previousProfitMinor;
    final onlySales = pnl.incomeMinor == report.salesMinor;
    final change = before > 0 && pnl.income.isNotEmpty
        ? ((profit - before) * 100 / before).round()
        : null;
    final compared = switch (change) {
      null => null,
      0 => 'same as ${report.previousLabel}',
      > 0 => 'up $change% on ${report.previousLabel}',
      _ => 'down ${-change}% on ${report.previousLabel}',
    };
    final label = switch (range) {
      ReportRange.thisMonth => 'Profit this month',
      ReportRange.lastMonth => 'Profit last month',
      ReportRange.threeMonths => 'Profit over 3 months',
    };
    return Card(
      key: const Key('insights-profit'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${profit < 0 ? '-' : ''}${plain(profit.abs())}',
              style: AppTypography.headlineFigure(theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${onlySales ? 'Sales' : 'In'} ${plain(pnl.incomeMinor)}',
                'costs ${plain(pnl.costsMinor)}',
                ?compared,
              ].join(' · '),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowPeoplePay extends StatelessWidget {
  const _HowPeoplePay(this.report, {required this.plain});

  final BusinessReport report;
  final String Function(int minor) plain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final total = report.salesMinor;
    final ways = report.byWay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      key: const Key('insights-ways'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('How people pay', padding: _cardTitlePadding),
            for (final MapEntry(:key, :value) in ways)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        methodLabel(key),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total <= 0 ? 0 : value / total,
                          minHeight: 8,
                          backgroundColor: colors.border,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        plain(value),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BestSellers extends StatelessWidget {
  const _BestSellers(this.report, {required this.plain});

  final BusinessReport report;
  final String Function(int minor) plain;

  String _detail(SoldLine s) {
    final unit = s.unit;
    final q = quantityText(s.quantityMilli);
    final sold = unit == null ? q : '$q ${unitFor(unit, s.quantityMilli)}';
    if (s.service) return '$sold · no stock';
    if (s.quantityMilli <= 0) return sold;
    final each = (s.profitMinor * 1000 / s.quantityMilli).round();
    return unit == null
        ? '$sold · profit ${plain(each)} each'
        : '$sold · profit ${plain(each)} / $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      key: const Key('insights-best-sellers'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Best sellers', padding: _cardTitlePadding),
            for (final (i, s) in report.bestSellers.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: EdgeInsets.only(
                  top: i > 0 ? 10 : 0,
                  bottom: i < report.bestSellers.length - 1 ? 10 : 0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.service ? '${s.name} (service)' : s.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _detail(s),
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      plain(s.amountMinor),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SalesByDay extends StatelessWidget {
  const _SalesByDay(this.byWeekday);

  /// Monday first.
  final List<int> byWeekday;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final most = byWeekday.fold(0, (m, v) => v > m ? v : m);
    final best = byWeekday.indexOf(most);
    return Card(
      key: const Key('insights-by-day'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Sales by day', padding: _cardTitlePadding),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        label: _names[i],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: most <= 0
                                  ? 4
                                  : 4 + 92 * byWeekday[i] / most,
                              decoration: BoxDecoration(
                                color: i == best
                                    ? theme.colorScheme.primary
                                    : colors.brandSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _letters[i],
                              style: theme.textTheme.labelMedium!.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sentences extends StatelessWidget {
  const _Sentences(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('insights-sentences'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          children: [
            for (final (i, l) in lines.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: EdgeInsets.only(
                  top: i > 0 ? 12 : 0,
                  bottom: i < lines.length - 1 ? 12 : 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6, right: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Text(l, style: theme.textTheme.bodyLarge)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The space under a card's title, before its rows.
const _cardTitlePadding = EdgeInsets.only(bottom: 12);

/// What the business may owe in tax, opening the Tax screen.
class _TaxCard extends ConsumerWidget {
  const _TaxCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final view = ref.watch(taxViewProvider).value;
    final hidden = AmountsHidden.of(context);
    final owed = view?.owedMinor;
    return Card(
      child: ListTile(
        key: const Key('insights-tax'),
        title: const Text('Tax you may owe'),
        subtitle: Text(
          'An estimate from your records',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        trailing: owed == null
            ? const Icon(Icons.chevron_right)
            : Text(
                moneyOrHidden(owed, hidden: hidden, withCurrency: false),
                style: AppTypography.rowAmount(theme.colorScheme.onSurface),
              ),
        onTap: () => context.push(AppRoutes.tax),
      ),
    );
  }
}
