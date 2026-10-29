import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/plan/plan_groups.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../debts/presentation/debts_screen.dart' show monthLabel;
import '../application/plan_providers.dart';
import 'payday_banner.dart';
import 'plan_item_sheet.dart';

/// Plan tab: what's coming, and is it covered?
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _pendingOnly = false;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(planMonthProvider);
    final current = ref.watch(currentMonthProvider);
    final view = ref.watch(planViewProvider(month));
    final names = {
      for (final c in ref.watch(planCategoriesProvider).value ?? <Category>[])
        c.id: c.name,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _Header(month),
            if (month == current) const PaydayBanner(),
            const SizedBox(height: 16),
            ...switch (view) {
              AsyncData(:final value) => _body(context, value, names),
              AsyncError() => [
                const Text('Plan could not load. Pull down or reopen Plan.'),
              ],
              _ => [
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    PlanView view,
    Map<int, String> names,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final rows = [
      for (final row in view.categoryRows)
        if (!_pendingOnly || row.status != PlanStatus.done) row,
    ];

    return [
      _IncomeCard(view),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: Text('By category', style: theme.textTheme.titleLarge),
          ),
          TextButton(
            onPressed: () => setState(() => _pendingOnly = !_pendingOnly),
            style: TextButton.styleFrom(foregroundColor: colors.link),
            child: Text(_pendingOnly ? 'Show all' : 'Pending only'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _CategoryList(
        rows: rows,
        names: names,
        emptyText: view.categoryRows.isEmpty
            ? 'Add rent, salary and other bills below to see how each '
                  'category is doing.'
            : 'Every category is done.',
      ),
      const SizedBox(height: 16),
      _SurplusCard(view),
      const SizedBox(height: 24),
      if (view.isClosed)
        Text(
          'This month is closed. Its figures were frozen at month end, and '
          'unpaid bills moved to the next month as arrears.',
          style: theme.textTheme.bodySmall,
        )
      else
        _LinesSection(view: view, names: names),
    ];
  }
}

class _Header extends ConsumerWidget {
  const _Header(this.month);

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(planMonthProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            identifier: SemanticIds.titlePlan,
            child: Text('Plan', style: theme.textTheme.headlineLarge),
          ),
        ),
        _RoundButton(
          tooltip: 'Previous month',
          icon: Icons.chevron_left,
          onPressed: () => notifier.show(month.previous),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(monthLabel(month), style: theme.textTheme.titleMedium),
        ),
        _RoundButton(
          tooltip: 'Next month',
          icon: Icons.chevron_right,
          onPressed: () => notifier.show(month.next),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface,
        side: BorderSide(color: colors.border),
        minimumSize: const Size.square(BrandTokens.touchTarget),
      ),
    );
  }
}

String _amount(int minor) => formatMoney(Money(minor), withCurrency: false);

class _OutlinedCard extends StatelessWidget {
  const _OutlinedCard({required this.child, this.padding = 20});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

/// Colours for the income bar, darkest to lightest red, so neighbouring
/// groups stay apart. The legend names each one.
Color _groupColour(BuildContext context, PlanGroup group) {
  final scheme = Theme.of(context).colorScheme;
  final colors = PesaColors.of(context);
  return switch (group) {
    PlanGroup.debt => scheme.primary,
    PlanGroup.tax => colors.link,
    PlanGroup.living => Color.lerp(scheme.primary, scheme.onSurface, 0.45)!,
    PlanGroup.school => Color.lerp(colors.brandSoft, scheme.primary, 0.25)!,
    PlanGroup.savings => colors.success,
  };
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard(this.view);

  final PlanView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final plan = view.plan;
    final expected = plan.expectedIncomeMinor;
    final planned = plan.plannedOutgoingMinor;
    final scale = expected > planned ? expected : planned;

    final String? note;
    if (expected == 0) {
      note = 'Add your salary or other income to compare.';
    } else if (planned > expected) {
      note = '${_amount(planned - expected)} more than expected income.';
    } else {
      note = null;
    }

    return _OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Planned of expected income',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
              Text(
                _amount(expected),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _amount(planned),
            style: AppTypography.amount(
              size: 40,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final g in view.groups) ...[
                      Expanded(
                        flex: _flex(g.amountMinor, scale),
                        child: ColoredBox(
                          color: _groupColour(context, g.group),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    Expanded(
                      flex: scale == 0 ? 1 : _flex(scale - planned, scale),
                      child: ColoredBox(color: colors.border),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (view.groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final g in view.groups)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _groupColour(context, g.group),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${g.group.label} ${_amount(g.amountMinor)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(note, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  /// Flex out of 1,000, at least 1 so a small group still shows.
  static int _flex(int part, int whole) {
    if (whole <= 0 || part <= 0) return 0;
    final flex = part * 1000 ~/ whole;
    return flex < 1 ? 1 : flex;
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.rows,
    required this.names,
    required this.emptyText,
  });

  final List<CategoryRow> rows;
  final Map<int, String> names;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    if (rows.isEmpty) {
      return _OutlinedCard(
        child: Text(emptyText, style: theme.textTheme.bodyMedium),
      );
    }
    return _OutlinedCard(
      padding: 0,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: colors.border,
              ),
            _CategoryTile(rows[i], _categoryName(rows[i].categoryId, names)),
          ],
        ],
      ),
    );
  }
}

String _categoryName(int? id, Map<int, String> names) =>
    id == null ? uncategorisedName : names[id] ?? 'Removed category';

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.row, this.name);

  final CategoryRow row;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final colour = switch (row.status) {
      PlanStatus.done => colors.successText,
      PlanStatus.over => theme.colorScheme.primary,
      PlanStatus.inProgress => colors.warning,
    };
    final progress = row.plannedMinor <= 0
        ? 1.0
        : (row.actualMinor / row.plannedMinor).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
              Text(
                row.status.label,
                style: theme.textTheme.labelLarge!.copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: colour,
              backgroundColor: colors.border,
              borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_amount(row.actualMinor)} of ${_amount(row.plannedMinor)}',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// How the surplus is split, in words.
String surplusSplitLabel(int debtShareBasisPoints, {required bool hasDebt}) {
  if (!hasDebt) return 'All to savings';
  return switch (debtShareBasisPoints) {
    10000 => 'All to debt',
    7500 => 'Three quarters to debt, the rest to savings',
    5000 => 'Half to debt, half to savings',
    2500 => 'A quarter to debt, the rest to savings',
    0 => 'All to savings',
    _ => '${debtShareBasisPoints ~/ 100}% to debt, the rest to savings',
  };
}

class _SurplusCard extends ConsumerWidget {
  const _SurplusCard(this.view);

  final PlanView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final surplus = view.surplus;
    final short = surplus.shortfallMinor > 0;

    return _OutlinedCard(
      padding: 16,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.sync, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  short
                      ? 'Short by ${_amount(surplus.shortfallMinor)}'
                      : 'Surplus ${_amount(surplus.surplusMinor)}',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  short
                      ? 'The plan is more than expected income'
                      : surplusSplitLabel(
                          view.debtShareBasisPoints,
                          hasDebt: view.hasDebt,
                        ),
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!view.isClosed && view.hasDebt)
            TextButton(
              onPressed: () => _adjust(context, ref),
              style: TextButton.styleFrom(foregroundColor: colors.link),
              child: const Text('Adjust'),
            ),
        ],
      ),
    );
  }

  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => RadioGroup<int>(
        groupValue: view.debtShareBasisPoints,
        onChanged: (value) => Navigator.of(context).pop(value),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Split the surplus',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final share in const [10000, 7500, 5000, 2500, 0])
                RadioListTile<int>(
                  value: share,
                  title: Text(surplusSplitLabel(share, hasDebt: true)),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || chosen == view.debtShareBasisPoints) return;
    await ref
        .read(planRepositoryProvider)
        .setSurplusDebtShareBasisPoints(chosen);
    refreshPlan(ref);
  }
}

class _LinesSection extends StatelessWidget {
  const _LinesSection({required this.view, required this.names});

  final PlanView view;
  final Map<int, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final lines = [...view.plan.lines]..sort(_byDue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Bills, income and one-offs',
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  showPlanItemSheet(context, month: view.plan.month),
              style: TextButton.styleFrom(foregroundColor: colors.link),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          _OutlinedCard(
            child: Text(
              'Add what repeats, such as salary, rent and school fees, and '
              'one-offs for this month only.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          _OutlinedCard(
            padding: 0,
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: colors.border,
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(lines[i].name),
                    subtitle: Text(_describe(lines[i], names)),
                    trailing: Text(
                      _amount(lines[i].amountMinor),
                      style: theme.textTheme.titleSmall,
                    ),
                    onTap: () => showPlanItemSheet(
                      context,
                      month: view.plan.month,
                      line: lines[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static int _byDue(PlanLine a, PlanLine b) {
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != null && bDue != null) return aDue.compareTo(bDue);
    if (aDue != null) return -1;
    if (bDue != null) return 1;
    return a.name.compareTo(b.name);
  }

  static String _describe(PlanLine line, Map<int, String> names) {
    final category = _categoryName(line.categoryId, names);
    final what = switch (line.source) {
      PlanLineSource.recurring => 'Due ${dayLabel(line.dueDate!)}',
      PlanLineSource.oneOff => line.isMarkedPaid ? 'One-off, paid' : 'One-off',
      PlanLineSource.arrears =>
        line.isMarkedPaid ? 'Carried forward, paid' : 'Carried forward',
    };
    return '$what · $category';
  }
}

/// A day as Plan shows it, for example `5 Nov`.
String dayLabel(CalendarDate date) =>
    '${date.day} ${monthLabel(date.yearMonth).split(' ').first}';
