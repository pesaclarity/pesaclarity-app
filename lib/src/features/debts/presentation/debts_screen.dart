import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/debts/fuliza_tracker.dart';
import '../../../domain/debts/payoff_order.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../application/debts_overview_provider.dart';
import 'debt_sheet.dart';

export '../../../domain/time/date_labels.dart' show monthLabel;

/// Debts, one level under Goals: when will I be debt-free?
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(debtsOverviewProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleDebts,
          child: const Text('Debts'),
        ),
        actions: [
          if (overview != null)
            IconButton(
              tooltip: 'Add a debt',
              icon: const Icon(Icons.add),
              onPressed: () => showDebtSheet(context, today: overview.today),
            ),
        ],
      ),
      body: overview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (overview.debts.isEmpty)
                  _NoDebtsYet(overview)
                else ...[
                  _RemainingCard(overview),
                  const SizedBox(height: 16),
                  _StrategyPicker(overview),
                  const SizedBox(height: 16),
                  _DebtList(overview),
                ],
                if (overview.fuliza case final fuliza?) ...[
                  const SizedBox(height: 16),
                  _FulizaCard(fuliza),
                ],
                if (overview.debts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _WhatIfCard(overview),
                ],
              ],
            ),
    );
  }
}

class _NoDebtsYet extends StatelessWidget {
  const _NoDebtsYet(this.overview);

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HeroFigureCard(
          label: 'Debt-free by',
          figure: '—',
          caption:
              'Add loans, cards, Fuliza or money from family to see the '
              'month you will be debt-free.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showDebtSheet(context, today: overview.today),
          icon: const Icon(Icons.add),
          label: const Text('Add a debt'),
        ),
      ],
    );
  }
}

class _RemainingCard extends StatelessWidget {
  const _RemainingCard(this.overview);

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = scheme.onPrimary.withValues(alpha: 0.85);
    final plan = overview.plan;

    return Card(
      color: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius + 4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remaining',
              style: textTheme.bodyMedium!.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Text(
              formatMoney(Money(overview.remainingMinor)),
              style: AppTypography.amount(
                size: 34,
                weight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _planSummary(overview, plan),
              style: textTheme.bodyMedium!.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

String _planSummary(DebtsOverview overview, PayoffPlan plan) {
  final month = plan.debtFreeMonth;
  if (month == null || !plan.clearsAll) {
    final stuck = overview.debts
        .where((d) => plan.neverClears.contains(d.id))
        .map((d) => d.lender)
        .firstOrNull;
    return stuck == null
        ? 'Pay a little more each month to set a debt-free date.'
        : 'Pay more than the minimum on $stuck to clear it.';
  }
  final interest = plan.totalInterestMinor;
  return interest > 0
      ? 'Debt-free ${monthLabel(month)} · interest ahead about '
            '${_roughly(interest)}'
      : 'Debt-free ${monthLabel(month)}';
}

class _StrategyPicker extends ConsumerWidget {
  const _StrategyPicker(this.overview);

  final DebtsOverview overview;

  static const _hints = {
    PayoffStrategy.avalanche:
        'Highest interest first: the least interest paid.',
    PayoffStrategy.snowball: 'Smallest balance first: quick wins.',
    PayoffStrategy.custom: 'Your own order. Hold and drag a debt to move it.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategy = overview.preference.strategy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PayoffStrategy>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: PayoffStrategy.avalanche,
              label: Text('Avalanche'),
            ),
            ButtonSegment(
              value: PayoffStrategy.snowball,
              label: Text('Snowball'),
            ),
            ButtonSegment(value: PayoffStrategy.custom, label: Text('Custom')),
          ],
          selected: {strategy},
          onSelectionChanged: (choice) async {
            final container = ProviderScope.containerOf(context, listen: false);
            await saveDebtStrategy(
              container,
              choice.single,
              currentOrder: [for (final d in overview.debts) d.id],
            );
            refreshDebts(container);
          },
        ),
        const SizedBox(height: 8),
        Text(
          _hints[strategy]!,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: PesaColors.of(context).textMuted),
        ),
      ],
    );
  }
}

class _DebtList extends ConsumerWidget {
  const _DebtList(this.overview);

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = overview.debts;
    final custom = overview.preference.strategy == PayoffStrategy.custom;
    Widget row(Debt debt, int index) => _DebtRow(
      key: ValueKey(debt.id),
      debt: debt,
      payoff: overview.plan.debt(debt.id),
      paidFraction: overview.paidFraction(debt),
      showDivider: index < debts.length - 1,
      onTap: () => showDebtSheet(context, today: overview.today, debt: debt),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: custom
          ? ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: debts.length,
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(debts[i].id),
                index: i,
                child: row(debts[i], i),
              ),
              onReorderItem: (from, to) async {
                final ids = [for (final d in debts) d.id];
                ids.insert(to, ids.removeAt(from));
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                await container
                    .read(debtsRepositoryProvider)
                    .setCustomOrder(ids);
                refreshDebts(container);
              },
            )
          : Column(
              children: [
                for (var i = 0; i < debts.length; i++) row(debts[i], i),
              ],
            ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({
    required this.debt,
    required this.payoff,
    required this.paidFraction,
    required this.showDivider,
    required this.onTap,
    super.key,
  });

  final Debt debt;
  final DebtPayoff payoff;
  final double paidFraction;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final cleared = payoff.paidOffIn;

    final details = [
      if (debt.chargesInterest)
        '${_rateLabel(debt.annualRateBasisPoints)} p.a.'
      else
        'Interest-free',
      if (debt.minimumPaymentMinor > 0)
        '${formatMoney(Money(debt.minimumPaymentMinor), withCurrency: false)}'
            ' a month',
      if (cleared != null) 'cleared ${monthLabel(cleared)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        debt.lender,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      formatMoney(
                        Money(debt.balanceMinor),
                        withCurrency: false,
                      ),
                      style: AppTypography.amount(
                        size: 17,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: paidFraction,
                    minHeight: 6,
                    color: theme.colorScheme.primary,
                    backgroundColor: colors.brandSoft,
                    semanticsLabel: '${(paidFraction * 100).floor()}% paid',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  cleared == null
                      ? '$details · needs more than the minimum'
                      : details,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: cleared == null ? colors.warning : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (showDivider) const Divider(height: 1, indent: 18, endIndent: 18),
        ],
      ),
    );
  }
}

class _FulizaCard extends StatelessWidget {
  const _FulizaCard(this.fuliza);

  final FulizaTrackerMonth fuliza;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final usage = fuliza.usage;
    final draws = usage.drawCount == 1 ? '1 draw' : '${usage.drawCount} draws';
    final days = fuliza.daysOverdrawn == 1
        ? '1 day overdrawn'
        : '${fuliza.daysOverdrawn} days overdrawn';
    final fees = formatMoney(Money(usage.feesMinor), withCurrency: false);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.phone_android, color: colors.link),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fuliza in ${monthLabel(usage.month)}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$draws · $days · $fees in fees',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  if (fuliza.isClimbing) ...[
                    const SizedBox(height: 6),
                    Text(
                      'More than last month. Clearing it sooner saves fees.',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.link,
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

class _WhatIfCard extends StatefulWidget {
  const _WhatIfCard(this.overview);

  final DebtsOverview overview;

  @override
  State<_WhatIfCard> createState() => _WhatIfCardState();
}

class _WhatIfCardState extends State<_WhatIfCard> {
  var _steps = 0;

  /// One slider step: a round amount near a tenth of the monthly minimums.
  int get _stepMinor {
    final minimums = widget.overview.debts.fold(
      0,
      (sum, d) => sum + d.minimumPaymentMinor,
    );
    final tenth = minimums ~/ 10;
    final round = Money.major(500).minorUnits;
    return tenth <= round ? round : (tenth ~/ round) * round;
  }

  static const _maxSteps = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final overview = widget.overview;
    final extra = _steps * _stepMinor;
    final month = overview.today.yearMonth;
    final comparison = PayoffComparison.whatIf(
      overview.debts,
      base: overview.preference.options(month),
      scenario: overview.preference.options(month, extraMonthlyMinor: extra),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'What if I add more a month?',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '+${formatMoney(Money(extra), withCurrency: false)}',
                  style: AppTypography.amount(
                    size: 17,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            Slider(
              value: _steps.toDouble(),
              max: _maxSteps.toDouble(),
              divisions: _maxSteps,
              label: formatMoney(Money(extra), withCurrency: false),
              onChanged: (v) => setState(() => _steps = v.round()),
            ),
            Text(
              _whatIfText(comparison, extra),
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

String _whatIfText(PayoffComparison comparison, int extra) {
  if (extra == 0) return 'Slide to see how much sooner you could be debt-free.';
  final month = comparison.plan.debtFreeMonth;
  if (month == null || !comparison.plan.clearsAll) {
    return 'Slide further to set a debt-free date.';
  }
  final sooner = comparison.monthsSooner;
  final saved = comparison.interestSavedMinor;
  final parts = [
    'Debt-free ${monthLabel(month)}',
    if (sooner != null && sooner > 0)
      sooner == 1 ? 'a month sooner' : '$sooner months sooner',
    if (saved != null && saved > 0) 'about ${_roughly(saved)} less interest',
  ];
  return '${parts.join(', ')}.';
}

String _rateLabel(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final hundredths = basisPoints % 100;
  if (hundredths == 0) return '$whole%';
  final text = hundredths.toString().padLeft(2, '0');
  return '$whole.${text.endsWith('0') ? text[0] : text}%';
}

/// An estimate in whole shillings, such as "about 1,900".
String _roughly(int minor) =>
    formatMoney(Money.major((minor / 100).round()), withCurrency: false);
