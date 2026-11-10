import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../security/application/balance_visibility.dart';
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
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final range = ref.watch(insightsRangeProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final period = periodFor(range, today);
    final report = ref.watch(businessReportProvider(period)).value;
    final hidden = ref.watch(balancesHiddenProvider);
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: SemanticIds.titleInsights,
                    child: Text(
                      'How it is doing',
                      style: theme.textTheme.headlineLarge,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('insights-full-records'),
                  onPressed: () => context.push(AppRoutes.fullRecords),
                  child: Text(
                    'Full records',
                    style: TextStyle(color: colors.link),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RangeMenu(
              selected: range,
              onSelected: (r) =>
                  ref.read(insightsRangeProvider.notifier).set(r),
            ),
            const SizedBox(height: 16),
            if (report == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
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
              if (report.insights.isNotEmpty) ...[
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

/// This month, Last month and 3 months, and Pick dates with [onCustom], as
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

  /// Whether "Pick dates" is the one chosen.
  final bool custom;

  /// Opens the dates to pick, each time "Pick dates" is chosen.
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ChoiceMenu<ReportRange?>(
      key: const Key('range'),
      name: 'Period',
      options: [
        for (final r in ReportRange.values) (r, r.label),
        if (onCustom != null) (null, 'Pick dates'),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              '${BaseCurrency.code} ${profit < 0 ? '−' : ''}'
              '${plain(profit.abs())}',
              style: AppTypography.amount(
                size: 32,
                color: theme.colorScheme.onSurface,
              ),
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

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('How people pay'),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Best sellers'),
            for (final (i, s) in report.bestSellers.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
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
                      style: theme.textTheme.titleMedium,
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Sales by day'),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          children: [
            for (final (i, l) in lines.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
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

/// What the business may owe in tax, opening the Tax screen.
class _TaxCard extends ConsumerWidget {
  const _TaxCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final view = ref.watch(taxViewProvider).value;
    final hidden = ref.watch(balancesHiddenProvider);
    final owed = view?.owedMinor;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: const Key('insights-tax'),
        title: const Text('Tax you may owe'),
        subtitle: Text(
          'An estimate from your records',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (owed != null)
              Text(
                hidden
                    ? maskedDigits
                    : formatMoney(Money(owed), withCurrency: false),
                style: theme.textTheme.titleMedium,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.push(AppRoutes.tax),
      ),
    );
  }
}
