import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/health/health_index.dart';
import '../../../domain/insights/findings.dart';
import '../../../domain/insights/insights_summary.dart';
import '../../../domain/insights/leakage.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../home/application/health_index_provider.dart';
import '../application/insights_providers.dart';
import '../application/insights_report.dart';
import '../application/month_labels.dart';
import '../application/report_sharer.dart';
import '../application/tag_totals_provider.dart';
import 'health_pillar_sheet.dart';
import 'spending_charts_card.dart';
import 'tag_totals_card.dart';

String _amount(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: false);

String _amountOr(bool hidden, int minor) =>
    moneyOrHidden(minor, hidden: hidden, withCurrency: false);

/// Insights tab: what should I change?
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  var _sharing = false;

  Future<void> _shareReport() async {
    setState(() => _sharing = true);
    try {
      final summary = await ref.read(insightsSummaryProvider.future);
      final health = await ref.read(healthIndexProvider.future);
      final tags = await ref.read(tagTotalsThisMonthProvider.future);
      final names = await ref.read(tagNamesProvider.future);
      final report = InsightsReport(
        summary: summary,
        createdAt: ref.read(clockProvider)(),
        health: health?.index,
        healthChange: health?.change,
        tags: tagSpends(tags, names),
      );
      final bytes = await ref.read(reportRendererProvider)(report);
      await ref
          .read(reportSharerProvider)
          .sharePdf(bytes, fileName: report.fileName, subject: report.title);
    } on Object {
      if (mounted) showNote(context, 'The report was not made. Try again.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(insightsSummaryProvider);
    // Kept listened while the tab is open so the report has them ready,
    // even when the tags card is scrolled out of view.
    ref
      ..watch(tagNamesProvider)
      ..watch(tagTotalsThisMonthProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Layout.gutter,
            16,
            Layout.gutter,
            Layout.tabBottom,
          ),
          children: [
            TabHeader(
              'Insights',
              semanticsId: SemanticIds.titleInsights,
              actions: [
                // Looks like the export button, but shares the report
                // straight away.
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: 'Export monthly report as PDF',
                    child: OutlinedButton.icon(
                      onPressed: summary.hasValue && !_sharing
                          ? _shareReport
                          : null,
                      icon: _sharing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 20),
                      label: const Text('Report'),
                    ),
                  ),
                ),
                const AmountsEye(),
              ],
            ),
            ...switch (summary) {
              AsyncData(:final value) => _insights(value),
              AsyncError() => [
                ErrorView(
                  'Insights could not load.',
                  onRetry: () => ref.invalidate(insightsSummaryProvider),
                ),
              ],
              _ => [const LoadingView(inList: true)],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _insights(InsightsSummary summary) => [
    if (!summary.hasData)
      const _EmptyCard()
    else ...[
      const _FindingsSection(),
      const SectionTitle('Spending'),
      SpendingChartsSection(trend: summary.trend),
      const SizedBox(height: Layout.cardGap),
      _LeakageCard(summary),
      const SectionTitle('Financial Health Index'),
      const _HealthCard(),
    ],
    const TagTotalsSection(),
  ];
}

/// This month's changes against the same days of last month; each opens
/// the transactions behind it.
class _FindingsSection extends ConsumerWidget {
  const _FindingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final findings = ref.watch(findingsProvider).value ?? const <Finding>[];
    if (findings.isEmpty) return const SizedBox.shrink();
    final names = ref.watch(categoryNamesProvider).value ?? const {};
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('What changed'),
        Card(
          child: Column(
            children: [
              for (final (i, f) in findings.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: Key('finding-$i'),
                  title: Text(
                    findingTitle(f, names, hidden: AmountsHidden.of(context)),
                  ),
                  subtitle: Text(
                    findingDetail(f, hidden: AmountsHidden.of(context)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.go(AppRoutes.activityWith(f.filterFor(today))),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Food up 2,300 on last month", "Fees 1,200 so far".
String findingTitle(Finding f, Map<int, String> names, {bool hidden = false}) =>
    switch (f) {
      CategoryFinding(:final slice, :final changeMinor) =>
        '${sliceLabel(slice, names)} ${changeMinor > 0 ? 'up' : 'down'} '
            '${_amountOr(hidden, changeMinor.abs())} on last month',
      FeesFinding(:final nowMinor) =>
        'Fees ${_amountOr(hidden, nowMinor)} so far',
      IncomeFinding(:final nowMinor) =>
        'Money in ${_amountOr(hidden, nowMinor)} so far',
    };

/// "22,800 so far this month", "300 more than last month".
String findingDetail(Finding f, {bool hidden = false}) => switch (f) {
  CategoryFinding(:final nowMinor) =>
    '${_amountOr(hidden, nowMinor)} so far this month',
  _ => switch (f.changeMinor) {
    0 => 'Same as last month',
    > 0 => '${_amountOr(hidden, f.changeMinor)} more than last month',
    _ => '${_amountOr(hidden, -f.changeMinor)} less than last month',
  },
};

/// Before anything is read: one button, to choose the accounts. A
/// statement to import is in the + menu.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your insights show here', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Once your messages or a statement are read, this fills with '
              'what changed, where your money goes and your health score.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('insights-accounts'),
              onPressed: () => context.go(AppRoutes.chooseAccounts),
              child: const Text('Choose my accounts'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeakageCard extends StatelessWidget {
  const _LeakageCard(this.summary);

  final InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final current = summary.current;
    final share = current.leakageShareBasisPoints;
    final previous = summary.previous;
    final sentence = leakageSentence(
      summary,
      previousMonthName: previous == null ? null : monthName(previous.month),
    );

    return Card(
      // Picked out with a brand-coloured edge.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: .3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leakage in ${monthName(current.month)}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              children: [
                Text(
                  _amount(context, current.leakageMinor),
                  style: AppTypography.headlineFigure(
                    theme.colorScheme.onSurface,
                  ),
                ),
                if (share != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${percentLabel(share)} of income',
                      style: theme.textTheme.labelLarge!.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            if (sentence.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(sentence, style: theme.textTheme.bodyMedium),
            ],
            if (current.leakage.groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in current.leakage.groups)
                    Chip(
                      label: Text(
                        '${g.label} ${_amount(context, g.amountMinor)}',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled amount over a bar scaled to [fraction] of the full width.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                value,
                style: AppTypography.rowAmount(theme.colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: colors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends ConsumerWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final health = ref.watch(healthIndexProvider).value;
    if (health == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Text(
            'Your score shows once a full month of transactions has been '
            'read.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
      );
    }
    final index = health.index;
    final action = index.bestAction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${monthName(index.month)} ${index.month.year}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${index.band.label}.'
                        '${healthChangeSentence(health.change)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${index.score}',
                  semanticsLabel: 'Score ${index.score} of 100',
                  style: AppTypography.headlineFigure(
                    theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            for (final pillar in HealthPillar.values) ...[
              const SizedBox(height: 6),
              InkWell(
                key: Key('pillar-${pillar.name}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => showHealthPillar(context, index, pillar),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: _BarRow(
                    label: pillar.label,
                    value: '${pillarPoints(index, pillar)} of 25',
                    fraction: index.pillarCentipoints(pillar) / 2500,
                    color: pillar == index.weakestPillar
                        ? theme.colorScheme.primary
                        : colors.textMuted,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(Layout.panelRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Layout.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What helps most',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(action.message, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        action.gainPoints == 1
                            ? 'Adds up to 1 point.'
                            : 'Adds up to ${action.gainPoints} points.',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
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
    );
  }
}
