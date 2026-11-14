import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/debts/fuliza_tracker.dart';
import '../../../domain/debts/payoff_order.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/presentation/fuliza_paid.dart';
import '../application/debts_overview_provider.dart';
import 'debt_row.dart';
import 'debt_sheet.dart';

export '../../../domain/time/date_labels.dart' show monthLabel;

/// Debts, one level under Goals: when will I be debt-free?
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(debtsOverviewProvider);
    final overview = state.value;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleDebts,
          child: const Text('Debts'),
        ),
        actions: [
          if (overview != null)
            AddButton(
              tooltip: 'Add a debt',
              onPressed: () => showDebtSheet(context, today: overview.today),
            ),
          const AmountsEye(),
          const SizedBox(width: 8),
        ],
      ),
      body: overview == null
          ? state.hasError
                ? ErrorView(
                    'Your debts could not load.',
                    onRetry: () => refreshDebts(
                      ProviderScope.containerOf(context, listen: false),
                    ),
                  )
                : const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Layout.gutter,
                8,
                Layout.gutter,
                Layout.screenBottom,
              ),
              children: [
                if (overview.debts.isEmpty)
                  const _NoDebtsYet()
                else ...[
                  _RemainingCard(overview),
                  const SizedBox(height: Layout.cardGap),
                  _StrategyPicker(overview),
                  const SizedBox(height: Layout.cardGap),
                  _DebtList(overview),
                ],
                if (overview.fulizaDebt case final owed?) ...[
                  const SizedBox(height: Layout.cardGap),
                  _FulizaOwedCard(
                    owed,
                    today: overview.today,
                    account: overview.fulizaAccount,
                    walletMinor: overview.fulizaWalletMinor,
                  ),
                ],
                if (overview.fuliza case final fuliza?) ...[
                  const SizedBox(height: Layout.cardGap),
                  _FulizaCard(fuliza),
                ],
                if (overview.debts.isNotEmpty) ...[
                  const SizedBox(height: Layout.cardGap),
                  _WhatIfCard(overview),
                ],
              ],
            ),
    );
  }
}

class _NoDebtsYet extends StatelessWidget {
  const _NoDebtsYet();

  @override
  Widget build(BuildContext context) {
    return const HeroFigureCard(
      label: 'Debt-free by',
      caption:
          'Add loans, cards, Fuliza or money from family to see the '
          'month you will be debt-free.',
    );
  }
}

class _RemainingCard extends StatelessWidget {
  const _RemainingCard(this.overview);

  final DebtsOverview overview;

  @override
  Widget build(BuildContext context) {
    return HeroFigureCard(
      label: 'Remaining',
      figure: shownMoney(context, overview.remainingMinor, withCurrency: true),
      caption: _planSummary(overview, overview.plan),
      // The app bar has the eye.
      showEye: false,
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
        AdaptiveSegmented<PayoffStrategy>(
          name: 'Payoff order',
          showSelectedIcon: false,
          segments: const [
            (PayoffStrategy.avalanche, 'Avalanche'),
            (PayoffStrategy.snowball, 'Snowball'),
            (PayoffStrategy.custom, 'Custom'),
          ],
          selected: strategy,
          onChanged: (choice) async {
            final container = ProviderScope.containerOf(context, listen: false);
            await saveDebtStrategy(
              container,
              choice,
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
    Widget row(Debt debt, int index) => Column(
      key: ValueKey(debt.id),
      mainAxisSize: MainAxisSize.min,
      children: [
        _DebtItem(
          debt: debt,
          payoff: overview.plan.debt(debt.id),
          paidFraction: overview.paidFraction(debt),
          onTap: () =>
              showDebtSheet(context, today: overview.today, debt: debt),
        ),
        if (index < debts.length - 1) const Divider(height: 1),
      ],
    );

    return Card(
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

class _DebtItem extends StatelessWidget {
  const _DebtItem({
    required this.debt,
    required this.payoff,
    required this.paidFraction,
    required this.onTap,
  });

  final Debt debt;
  final DebtPayoff payoff;
  final double paidFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final cleared = payoff.paidOffIn;

    final details = [
      if (debt.chargesInterest)
        '${_rateLabel(debt.annualRateBasisPoints)} p.a.'
      else
        'Interest-free',
      if (debt.minimumPaymentMinor > 0)
        '${shownMoney(context, debt.minimumPaymentMinor, withCurrency: false)}'
            ' a month',
      if (cleared != null) 'cleared ${monthLabel(cleared)}',
    ].join(' · ');

    return DebtRow(
      name: debt.lender,
      amount: shownMoney(context, debt.balanceMinor, withCurrency: false),
      paidFraction: paidFraction,
      caption: cleared == null
          ? '$details · needs more than the minimum'
          : details,
      captionColor: cleared == null ? colors.warning : null,
      onTap: onTap,
    );
  }
}

/// Fuliza owed now: a debt, taken off M-Pesa in Balances and On hand.
class _FulizaOwedCard extends StatelessWidget {
  const _FulizaOwedCard(
    this.debt, {
    required this.today,
    required this.account,
    required this.walletMinor,
  });

  final FulizaDebt debt;
  final CalendarDate today;
  final AccountOpening? account;
  final int walletMinor;

  @override
  Widget build(BuildContext context) {
    final due = debt.dueAt;
    final charges = debt.chargesIn(today.yearMonth);
    final details = [
      if (due != null) 'Due ${dayLabel(CalendarDate.local(due))}',
      if (charges > 0)
        '${shownMoney(context, charges, withCurrency: false)} in daily '
            'charges this month',
      'Taken off M-Pesa in Balances',
    ].join(' · ');
    final on = account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DebtRow(
          key: const Key('debts-fuliza-owed'),
          name: 'Fuliza',
          amount: shownMoney(context, debt.owedMinor, withCurrency: false),
          paidFraction: 0,
          caption: details,
        ),
        if (on != null)
          FulizaPaidButton(
            accountId: on.id,
            walletMinor: walletMinor,
            owedMinor: debt.owedMinor,
            currency: on.currency,
          ),
      ],
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
    final fees = shownMoney(context, usage.feesMinor, withCurrency: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconBadge(Icons.phone_android_outlined),
            const SizedBox(width: 12),
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
                      style: theme.textTheme.bodySmall,
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
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
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
                  '+${shownMoney(context, extra, withCurrency: false)}',
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
              ],
            ),
            Slider(
              value: _steps.toDouble(),
              max: _maxSteps.toDouble(),
              divisions: _maxSteps,
              label: shownMoney(context, extra, withCurrency: false),
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
