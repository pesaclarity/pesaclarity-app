import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/goals/debt_progress.dart';
import '../../../domain/goals/net_worth.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/progress_ring.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../lending/application/lending_providers.dart';
import '../application/goals_overview_provider.dart';
import 'goal_sheet.dart';

/// Goals tab: am I getting there?
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(goalsOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleGoals,
          child: const Text('Goals'),
        ),
      ),
      body: switch (overview) {
        AsyncData(:final value) => _GoalsBody(value),
        AsyncError() => Center(
          child: TextButton(
            onPressed: () =>
                refreshGoals(ProviderScope.containerOf(context, listen: false)),
            child: const Text('Goals could not load. Tap to try again.'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _GoalsBody extends ConsumerWidget {
  const _GoalsBody(this.overview);

  final GoalsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = overview.debts.open;
    return RefreshIndicator(
      onRefresh: () async {
        refreshGoals(ProviderScope.containerOf(context, listen: false));
        await ref.read(goalsOverviewProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _DebtFreeCard(overview),
          _SectionHeader(
            'Debts',
            action: TextButton(
              onPressed: () => context.go(AppRoutes.debts),
              child: const Text('See debts'),
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
          _SectionHeader(
            'Saving for',
            action: TextButton(
              onPressed: () => showGoalSheet(context, today: overview.today),
              child: const Text('Add a goal'),
            ),
          ),
          if (overview.goals.isEmpty)
            _LinkCard(
              title: 'Add a goal',
              subtitle: 'Such as an emergency fund or a new laptop.',
              onTap: () => showGoalSheet(context, today: overview.today),
            )
          else
            _GoalGrid(goals: overview.goals, today: overview.today),
          const SizedBox(height: 14),
          _NetWorthCard(overview.netWorth),
          const SizedBox(height: 14),
          _LendingCard(overview.lending),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _DebtFreeCard extends StatelessWidget {
  const _DebtFreeCard(this.overview);

  final GoalsOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
          '${formatMoney(Money(debts.remainingMinor), withCurrency: false)} '
          'left · ${debts.clearedCount} of ${debts.count} cleared';
    }
    final muted = scheme.onPrimary.withValues(alpha: 0.85);

    return Card(
      color: scheme.primary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius + 4),
      ),
      child: InkWell(
        onTap: () => context.go(AppRoutes.debts),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (hasDebts) ...[
                ProgressRing(
                  value: debts.paidFraction,
                  size: 92,
                  strokeWidth: 10,
                  color: scheme.onPrimary,
                  trackColor: scheme.shadow.withValues(alpha: 0.25),
                  semanticsLabel: '$percent% of debt paid',
                  child: Text(
                    '$percent%',
                    style: AppTypography.amount(
                      size: 20,
                      weight: FontWeight.w700,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.bodyMedium!.copyWith(color: muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      figure,
                      style: AppTypography.amount(
                        size: 30,
                        weight: FontWeight.w700,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      style: textTheme.bodyMedium!.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
    final colors = PesaColors.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colors.border,
              ),
            _DebtRow(line: lines[i], plan: plan, today: today),
          ],
        ],
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.line, required this.plan, required this.today});

  final DebtLine line;
  final PayoffPlan? plan;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: () => context.go(AppRoutes.debts),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.debt.lender,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatMoney(
                    Money(line.debt.balanceMinor),
                    withCurrency: false,
                  ),
                  style: AppTypography.amount(
                    size: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: line.paidFraction,
                minHeight: 6,
                color: theme.colorScheme.primary,
                backgroundColor: colors.border,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              debtCaption(line, plan: plan, today: today),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
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
          : 'next ${formatMoney(Money(next.amountMinor), withCurrency: false)}, '
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
        const gap = 12.0;
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
    String amount(int minor) =>
        formatMoney(Money(minor, currency: goal.currency), withCurrency: false);
    final percent = (goal.progress * 100).floor();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showGoalSheet(context, today: today, goal: goal),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProgressRing(
                value: goal.progress,
                color: goal.isReached ? colors.success : colors.link,
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
              if (goalPace(goal, today) case final pace?) ...[
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
String? goalPace(SavingsGoal goal, CalendarDate today) {
  if (goal.isReached) return 'Reached';
  final needed = goal.monthlyNeededMinor(today);
  final date = goal.targetDate;
  if (needed == null || date == null) return null;
  final amount = formatMoney(
    Money(needed, currency: goal.currency),
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
        '${formatMoney(Money(change), withCurrency: false)} this month';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net worth', style: theme.textTheme.bodySmall),
                  Text(
                    formatMoney(
                      Money(netWorth.valueMinor),
                      withCurrency: false,
                    ),
                    style: AppTypography.amount(
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              changeText,
              style: theme.textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: change >= 0 ? colors.success : theme.colorScheme.error,
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
    String kes(int minor) => formatMoney(Money(minor), withCurrency: false);
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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
