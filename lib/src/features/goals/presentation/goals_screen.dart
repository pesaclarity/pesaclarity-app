import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/goals/debt_progress.dart';
import '../../../domain/goals/net_worth.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../debts/presentation/debt_row.dart';
import '../../lending/application/lending_providers.dart';
import '../application/goals_overview_provider.dart';
import 'goal_sheet.dart';

/// Goals tab: am I getting there?
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(goalsOverviewProvider);
    void retry() =>
        refreshGoals(ProviderScope.containerOf(context, listen: false));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            retry();
            try {
              await ref.read(goalsOverviewProvider.future);
            } on Object {
              // The list then says it could not load.
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Layout.gutter,
              16,
              Layout.gutter,
              Layout.tabBottom,
            ),
            children: [
              const TabHeader(
                'Goals',
                semanticsId: SemanticIds.titleGoals,
                actions: [AmountsEye()],
              ),
              ...switch (overview) {
                AsyncData(:final value) => _goals(context, value),
                AsyncError() => [
                  ErrorView('Your goals could not load.', onRetry: retry),
                ],
                _ => [const LoadingView(inList: true)],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _goals(BuildContext context, GoalsOverview overview) {
    final open = overview.debts.open;
    return [
      _DebtFreeCard(overview),
      SectionTitle(
        'Debts',
        action: Semantics(
          identifier: SemanticIds.goalsSeeDebts,
          child: TextButton(
            onPressed: () => context.go(AppRoutes.debts),
            child: const Text('See debts'),
          ),
        ),
      ),
      if (open.isEmpty)
        _LinkCard(
          title: 'Add a debt',
          subtitle: 'Loans, cards, Fuliza and family loans.',
          onTap: () => context.go(AppRoutes.debts),
        )
      else
        _DebtsCard(
          lines: open,
          plan: overview.plan?.plan,
          today: overview.today,
        ),
      SectionTitle(
        'Saving for',
        action: TextButton(
          onPressed: () => showGoalSheet(context, today: overview.today),
          child: const Text('Add a goal'),
        ),
      ),
      if (overview.goals.isEmpty)
        const EmptyNote(
          'Goals show here, such as an emergency fund or a new laptop.',
        )
      else ...[
        _GoalGrid(goals: overview.goals, today: overview.today),
        const SizedBox(height: Layout.cardGap),
      ],
      _NetWorthCard(overview.netWorth),
      const SizedBox(height: Layout.cardGap),
      _LendingCard(overview.lending),
    ];
  }
}

class _DebtFreeCard extends StatelessWidget {
  const _DebtFreeCard(this.overview);

  final GoalsOverview overview;

  @override
  Widget build(BuildContext context) {
    final debts = overview.debts;
    final percent = (debts.paidFraction * 100).floor();
    final month = overview.plan?.plan.debtFreeMonth;

    final String label;
    final String figure;
    final String caption;
    final hasDebts = debts.count > 0;
    if (!hasDebts) {
      label = 'Debts';
      figure = 'Add a debt';
      caption = 'See the month you will be debt-free.';
    } else if (debts.remainingMinor == 0) {
      label = 'Debts';
      figure = 'Debt-free';
      caption = 'All ${debts.count} cleared.';
    } else {
      label = 'Debt-free by';
      figure = month == null ? 'Not yet' : monthLabel(month);
      caption =
          '${shownMoney(context, debts.remainingMinor, withCurrency: false)} '
          'left · ${debts.clearedCount} of ${debts.count} cleared';
    }

    return HeroFigureCard(
      label: label,
      figure: figure,
      caption: caption,
      // The tab's title row has the eye.
      showEye: false,
      footer: hasDebts
          ? Semantics(
              label: '$percent% of debt paid',
              excludeSemantics: true,
              child: HeroProgress(
                value: debts.paidFraction,
                label: '$percent% paid',
              ),
            )
          : null,
      onTap: () => context.go(AppRoutes.debts),
    );
  }
}

class _DebtsCard extends StatelessWidget {
  const _DebtsCard({
    required this.lines,
    required this.plan,
    required this.today,
  });

  final List<DebtLine> lines;
  final PayoffPlan? plan;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final hidden = AmountsHidden.of(context);
    return Card(
      child: Column(
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const Divider(height: 1),
            DebtRow(
              name: line.debt.lender,
              amount: shownMoney(
                context,
                line.debt.balanceMinor,
                withCurrency: false,
              ),
              paidFraction: line.paidFraction,
              caption: debtCaption(
                line,
                plan: plan,
                today: today,
                hidden: hidden,
              ),
              onTap: () => context.go(AppRoutes.debts),
            ),
          ],
        ],
      ),
    );
  }
}

/// The line under a debt on Goals, such as `13% p.a. · cleared Jan` or
/// `Interest-free · in full, 31 Jan`.
String debtCaption(
  DebtLine line, {
  required PayoffPlan? plan,
  required CalendarDate today,
  bool hidden = false,
}) {
  final debt = line.debt;
  final parts = <String>[];
  if (!debt.isFormal) {
    parts.add('Interest-free');
  } else if (debt.annualRateBasisPoints > 0) {
    parts.add('${_percent(debt.annualRateBasisPoints)}% p.a.');
  }

  final next = debt.instalments.firstOrNull;
  if (next != null) {
    final day = dayLabel(next.dueDate, thisYear: today.year);
    parts.add(
      next.amountMinor >= debt.balanceMinor
          ? 'in full, $day'
          : 'next ${moneyOrHidden(hidden: hidden, next.amountMinor, withCurrency: false)}, '
                '$day',
    );
  } else {
    final month = plan?.debts
        .where((d) => d.debtId == debt.id)
        .firstOrNull
        ?.paidOffIn;
    if (month != null) {
      parts.add(
        today.yearMonth.monthsUntil(month) < 12
            ? 'cleared ${monthName(month)}'
            : 'cleared ${monthLabel(month)}',
      );
    }
  }
  return parts.join(' · ');
}

String _percent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final hundredths = basisPoints % 100;
  if (hundredths == 0) return '$whole';
  final fraction = hundredths.toString().padLeft(2, '0');
  return '$whole.${fraction.endsWith('0') ? fraction[0] : fraction}';
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({required this.goals, required this.today});

  final List<SavingsGoal> goals;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Layout.cardGap;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final goal in goals)
              SizedBox(
                width: width,
                child: _GoalCard(goal: goal, today: today),
              ),
          ],
        );
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.today});

  final SavingsGoal goal;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    String amount(int minor) => shownMoney(
      context,
      minor,
      currency: goal.currency,
      withCurrency: false,
    );
    final percent = (goal.progress * 100).floor();

    return Card(
      child: InkWell(
        onTap: () => showGoalSheet(context, today: today, goal: goal),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProgressRing(
                value: goal.progress,
                color: goal.isReached ? colors.successText : colors.link,
                trackColor: colors.border,
                semanticsLabel: '${goal.name} $percent%',
              ),
              const SizedBox(height: 10),
              Text(
                goal.name,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${amount(goal.savedMinor)} of ${amount(goal.targetMinor)}',
                style: theme.textTheme.bodySmall,
              ),
              if (goalPace(goal, today, hidden: AmountsHidden.of(context))
                  case final pace?) ...[
                const SizedBox(height: 2),
                Text(pace, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What a goal needs, such as `8,000 a month to Dec 2027`. Null for a goal
/// with no date that is still going.
String? goalPace(SavingsGoal goal, CalendarDate today, {bool hidden = false}) {
  if (goal.isReached) return 'Reached';
  final needed = goal.monthlyNeededMinor(today);
  final date = goal.targetDate;
  if (needed == null || date == null) return null;
  final amount = moneyOrHidden(
    hidden: hidden,
    needed,
    currency: goal.currency,
    withCurrency: false,
  );
  if (goal.monthsLeft(today) == 0) return '$amount to go, date passed';
  return '$amount a month to ${monthLabel(date.yearMonth)}';
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard(this.netWorth);

  final NetWorth netWorth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final change = netWorth.changeThisMonthMinor;
    final changeText =
        '${change > 0 ? '+' : ''}'
        '${shownMoney(context, change, withCurrency: false)} this month';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Net worth',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shownMoney(
                      context,
                      netWorth.valueMinor,
                      withCurrency: false,
                    ),
                    style: AppTypography.tileFigure(
                      theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              changeText,
              style: theme.textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: change >= 0
                    ? colors.successText
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LendingCard extends StatelessWidget {
  const _LendingCard(this.lending);

  final LendingOverview lending;

  @override
  Widget build(BuildContext context) {
    String kes(int minor) => shownMoney(context, minor, withCurrency: false);
    return _LinkCard(
      title: 'Lent and borrowed',
      subtitle: lending.isEmpty
          ? 'Keep track of money between you, friends and family.'
          : 'Owed to you ${kes(lending.owedToYouMinor)} · '
                'you owe ${kes(lending.youOweMinor)}',
      onTap: () => context.go(AppRoutes.lending),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
