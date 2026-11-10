import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/plan/plan_groups.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
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
          padding: const EdgeInsets.fromLTRB(
            Layout.gutter,
            16,
            Layout.gutter,
            Layout.tabBottom,
          ),
          children: [
            _Header(month),
            if (month == current) const PaydayBanner(),
            ...switch (view) {
              AsyncData(:final value) => _body(context, value, names),
              AsyncError() => [
                ErrorView(
                  'Your plan could not load.',
                  onRetry: () {
                    if (ref.read(monthCloseProvider).hasError) {
                      ref.invalidate(monthCloseProvider);
                    }
                    refreshPlan(ref);
                  },
                ),
              ],
              _ => [const LoadingView(inList: true)],
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
    final rows = [
      for (final row in view.categoryRows)
        if (!_pendingOnly || row.status != PlanStatus.done) row,
    ];

    return [
      _IncomeCard(view),
      SectionTitle(
        'By category',
        action: PillButton(
          label: _pendingOnly ? 'Show all' : 'Pending only',
          onPressed: () => setState(() => _pendingOnly = !_pendingOnly),
        ),
      ),
      _CategoryList(
        rows: rows,
        names: names,
        emptyText: view.categoryRows.isEmpty
            ? 'Add rent, salary and other bills below to see how each '
                  'category is doing.'
            : 'Every category is done.',
      ),
      const SizedBox(height: Layout.cardGap),
      _SurplusCard(view),
      if (view.isClosed) ...[
        const SizedBox(height: 24),
        Text(
          'This month is closed. Its figures were frozen at month end, and '
          'unpaid bills moved to the next month as arrears.',
          style: theme.textTheme.bodySmall,
        ),
      ] else
        _LinesSection(view: view, names: names),
    ];
  }
}

class _Header extends ConsumerWidget {
  const _Header(this.month);

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(planMonthProvider.notifier);
    return TabHeader(
      'Plan',
      semanticsId: SemanticIds.titlePlan,
      actions: [
        StepButton(
          tooltip: 'Previous month',
          icon: Icons.chevron_left,
          onPressed: () => notifier.show(month.previous),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            monthLabel(month),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        StepButton(
          tooltip: 'Next month',
          icon: Icons.chevron_right,
          onPressed: () => notifier.show(month.next),
        ),
        const AmountsEye(),
      ],
    );
  }
}

String _amount(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: false);

/// A card with [Layout.cardPadding] inside.
class _PaddedCard extends StatelessWidget {
  const _PaddedCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(Layout.cardPadding),
      child: child,
    ),
  );
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
      note =
          '${_amount(context, planned - expected)} more than expected income.';
    } else {
      note = null;
    }

    return _PaddedCard(
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
                _amount(context, expected),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _amount(context, planned),
            style: AppTypography.headlineFigure(theme.colorScheme.onSurface),
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
                        '${g.group.label} ${_amount(context, g.amountMinor)}',
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
    if (rows.isEmpty) return EmptyNote(emptyText);
    return Card(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            _CategoryTile(row, _categoryName(row.categoryId, names)),
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
      PlanStatus.over => colors.warning,
      PlanStatus.inProgress => theme.colorScheme.primary,
    };
    final progress = row.plannedMinor <= 0
        ? 1.0
        : (row.actualMinor / row.plannedMinor).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardPadding,
        vertical: 12,
      ),
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
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_amount(context, row.actualMinor)} of ${_amount(context, row.plannedMinor)}',
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

  static const _shares = [10000, 7500, 5000, 2500, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final surplus = view.surplus;
    final short = surplus.shortfallMinor > 0;
    final adjustable = !view.isClosed && view.hasDebt;
    final share = view.debtShareBasisPoints;
    final String? detail = short
        ? 'The plan is more than expected income'
        : adjustable
        ? null
        : surplusSplitLabel(share, hasDebt: view.hasDebt);

    return _PaddedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBadge(Icons.sync),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      short
                          ? 'Short by ${_amount(context, surplus.shortfallMinor)}'
                          : 'Surplus ${_amount(context, surplus.surplusMinor)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (adjustable) ...[
            const SizedBox(height: 12),
            ChoiceMenu<int>(
              key: const Key('plan-surplus-split'),
              name: 'Split the surplus',
              expand: true,
              options: [
                for (final option in {..._shares, share})
                  (option, surplusSplitLabel(option, hasDebt: true)),
              ],
              value: share,
              onChanged: (chosen) => _split(ref, chosen),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _split(WidgetRef ref, int chosen) async {
    if (chosen == view.debtShareBasisPoints) return;
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
    final month = view.plan.month;
    final lines = [...view.plan.lines]..sort(_byDue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Bills, income and one-offs',
          action: AddButton(
            tooltip: 'Add to ${monthLabel(month)}',
            onPressed: () => showPlanItemSheet(context, month: month),
          ),
        ),
        if (lines.isEmpty)
          const EmptyNote(
            'Add what repeats, such as salary, rent and school fees, and '
            'one-offs for this month only.',
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, line) in lines.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(line.name),
                    subtitle: Text(_describe(line, names)),
                    trailing: Text(
                      _amount(context, line.amountMinor),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                    onTap: () =>
                        showPlanItemSheet(context, month: month, line: line),
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
