import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/plan/upcoming_bills.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/presentation/add_transaction_sheet.dart';
import '../../security/application/balance_visibility.dart';
import '../../statements/data/pdf_text_extractor.dart';
import '../application/cash_flow_forecast_provider.dart';
import '../application/health_index_provider.dart';
import '../application/safe_to_spend_provider.dart';
import '../application/upcoming_bills_provider.dart';

/// Bills shown under Coming up before "See all".
const _billsShown = 3;

String _kes(BuildContext context, int minor) => _AmountsHidden.of(context)
    ? 'KES $maskedDigits'
    : formatMoney(Money(minor));

String _plain(BuildContext context, int minor) => _AmountsHidden.of(context)
    ? maskedDigits
    : formatMoney(Money(minor), withCurrency: false);

/// Masks every amount below it while balances are hidden.
class _AmountsHidden extends InheritedWidget {
  const _AmountsHidden({required this.hidden, required super.child});

  final bool hidden;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmountsHidden>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(_AmountsHidden oldWidget) =>
      hidden != oldWidget.hidden;
}

/// Home tab: how am I doing today?
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.nairobi(ref.watch(clockProvider)());
    final safeToSpend = ref.watch(safeToSpendTodayProvider).value;
    final health = ref.watch(healthIndexProvider).value;
    final forecast = ref.watch(cashFlowForecastProvider).value;
    final bills = ref.watch(upcomingBillsProvider).value ?? const [];
    final canImport = ref.watch(statementImportAvailableProvider);

    void openActivity(ActivityFilter filter) =>
        context.go(AppRoutes.activityWith(filter));

    final thisMonth = ActivityFilter(from: today.yearMonth.firstDay, to: today);
    final paceWindow = ActivityFilter(
      type: ActivityType.spending,
      from: today.addDays(-paceWindowDays),
      to: today,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _AmountsHidden(
          hidden: ref.watch(balancesHiddenProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              _Header(today: today),
              const SizedBox(height: 20),
              if (safeToSpend == null)
                const HeroFigureCard(
                  label: 'Safe to spend today',
                  figure: 'KES —',
                  caption:
                      'Shows once your messages have been read and Plan has '
                      'a day-to-day budget.',
                )
              else
                _SafeToSpendCard(
                  safeToSpend,
                  nextIncome: forecast?.nextIncome,
                  onTap: () => openActivity(
                    thisMonth.copyWith(type: ActivityType.dayToDay),
                  ),
                ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatTile(
                        label: 'Left this month',
                        value: safeToSpend == null
                            ? '—'
                            : _plain(context, safeToSpend.leftThisMonthMinor),
                        onTap: safeToSpend == null
                            ? null
                            : () => openActivity(
                                thisMonth.copyWith(type: ActivityType.dayToDay),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        label: 'Runway at this pace',
                        value: _runwayLabel(forecast),
                        onTap: forecast == null
                            ? null
                            : () => openActivity(paceWindow),
                      ),
                    ),
                  ],
                ),
              ),
              if (forecast != null) ...[
                const SizedBox(height: 12),
                _ForecastCard(forecast, onTap: () => openActivity(paceWindow)),
              ],
              if (health != null) ...[
                const SizedBox(height: 12),
                _HealthIndexCard(
                  health,
                  onTap: () {
                    final month = health.index.month;
                    openActivity(
                      ActivityFilter(from: month.firstDay, to: month.lastDay),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              _ComingUp(bills: bills, today: today),
            ],
          ),
        ),
      ),
      // Without a PDF engine (the F-Droid build) there is only one choice.
      floatingActionButton: FloatingActionButton(
        tooltip: canImport ? 'Add or import' : 'Add a transaction',
        shape: const CircleBorder(),
        onPressed: () => canImport
            ? _showAddMenu(context)
            : showAddTransactionSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _runwayLabel(CashFlowForecast? forecast) {
  final days = forecast?.runwayDays;
  if (days == null) return '—';
  if (days <= 0) return 'Today';
  return days == 1 ? '1 day' : '$days days';
}

Future<void> _showAddMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<_AddChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Add a transaction'),
            subtitle: const Text('Cash or anything a message missed'),
            onTap: () => Navigator.pop(context, _AddChoice.manual),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import a statement'),
            subtitle: const Text('M-Pesa or bank PDF, for older history'),
            onTap: () => Navigator.pop(context, _AddChoice.import),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _AddChoice.manual:
      await showAddTransactionSheet(context);
    case _AddChoice.import:
      context.go(AppRoutes.importStatement);
    case null:
      break;
  }
}

enum _AddChoice { manual, import }

class _Header extends StatelessWidget {
  const _Header({required this.today});

  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                longDate(today),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              Semantics(
                identifier: SemanticIds.titleHome,
                child: Text('Home', style: theme.textTheme.headlineMedium),
              ),
            ],
          ),
        ),
        Semantics(
          identifier: SemanticIds.homeProfile,
          child: IconButton.filled(
            tooltip: 'Profile',
            iconSize: 26,
            constraints: const BoxConstraints.tightFor(width: 52, height: 52),
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go(AppRoutes.profile),
          ),
        ),
      ],
    );
  }
}

class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard(this.result, {required this.onTap, this.nextIncome});

  final SafeToSpend result;
  final ScheduledFlow? nextIncome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onBrand = textTheme.bodyMedium!.copyWith(color: scheme.onPrimary);

    final today = result.today;
    final String detail;
    if (result.isBudgetUsedUp) {
      detail = 'This month\'s day-to-day budget is used up';
    } else if (result.overTodayMinor > 0) {
      detail = '${_kes(context, result.overTodayMinor)} over today\'s limit';
    } else if (today.isWeekend) {
      detail = 'Weekdays get ${_plain(context, result.weekdayLimitMinor)}';
    } else {
      detail = 'Weekend days get ${_plain(context, result.weekendLimitMinor)}';
    }
    final income = nextIncome;
    final payday = income == null
        ? ''
        : ' · ${_daysTo(today.daysUntil(income.date))} to payday';

    final budget = result.budgetMinor;
    final used = budget <= 0
        ? 0.0
        : ((budget - result.leftThisMonthMinor) / budget).clamp(0.0, 1.0);

    return Card(
      color: scheme.primary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius + 4),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Safe to spend today · '
                      '${today.isWeekend ? 'Weekend' : 'Weekday'}',
                      style: textTheme.labelLarge!.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final hidden = ref.watch(balancesHiddenProvider);
                      return IconButton(
                        tooltip: hidden ? 'Show balances' : 'Hide balances',
                        color: scheme.onPrimary,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          hidden ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            ref.read(balancesHiddenProvider.notifier).toggle(),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _kes(context, result.leftTodayMinor),
                style: AppTypography.amount(size: 44, color: scheme.onPrimary),
              ),
              const SizedBox(height: 10),
              Text('$detail$payday', style: onBrand),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 8,
                  color: scheme.onPrimary,
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${(used * 100).round()}% of this month\'s spending plan used',
                style: onBrand,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _daysTo(int days) => switch (days) {
  <= 0 => '0 days',
  1 => '1 day',
  _ => '$days days',
};

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: AppTypography.amount(
                  size: 28,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cash-flow forecast: when the money runs out at this pace, and any
/// known charge the balance would not cover.
class _ForecastCard extends StatelessWidget {
  const _ForecastCard(this.forecast, {required this.onTap});

  final CashFlowForecast forecast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = _AmountsHidden.of(context);
    final messages = [
      for (final m in forecast.messages) maskAmountsIf(hidden, m),
    ];
    final runsOut = forecast.zeroDate != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    runsOut ? Icons.trending_down : Icons.trending_flat,
                    color: runsOut ? colors.link : colors.successText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      messages.first,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              for (final warning in messages.skip(1)) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthIndexCard extends StatelessWidget {
  const _HealthIndexCard(this.health, {required this.onTap});

  final HealthOnHome health;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final index = health.index;
    final change = health.change;
    final String headline;
    if (change == null) {
      headline = 'Scored on ${monthName(index.month)}';
    } else if (change > 0) {
      headline = 'Up ${_points(change)} on the month before';
    } else if (change < 0) {
      headline = 'Down ${_points(-change)} on the month before';
    } else {
      headline = 'Same as the month before';
    }
    final action = index.bestAction;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: math.min(index.score, 100) / 100,
                        strokeWidth: 6,
                        color: theme.colorScheme.primary,
                        backgroundColor: colors.brandSoft,
                      ),
                    ),
                    Text(
                      '${index.score}',
                      style: AppTypography.amount(
                        size: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Financial health · ${index.band.label}',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    Text(headline, style: theme.textTheme.titleMedium),
                    if (action != null)
                      Text(
                        'Weakest: ${action.indicator.label.toLowerCase()}. '
                        '${action.message}',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.link,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

String _points(int n) => n == 1 ? '1 point' : '$n points';

class _ComingUp extends StatelessWidget {
  const _ComingUp({required this.bills, required this.today});

  final List<UpcomingBill> bills;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final shown = bills.take(_billsShown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Coming up', style: theme.textTheme.titleLarge),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.plan),
              child: Text('See all', style: TextStyle(color: colors.link)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
            side: BorderSide(color: colors.border),
          ),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Bills due in the next two weeks show here. '
                    'Add them in Plan.',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final (i, bill) in shown.indexed) ...[
                      if (i > 0) Divider(height: 1, color: colors.border),
                      _BillRow(bill: bill, today: today),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, required this.today});

  final UpcomingBill bill;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final due = bill.dueDate;
    final overdue = bill.isOverdueOn(today);
    final when = due == null
        ? 'Due this month'
        : 'Due ${shortDate(due)} · ${relativeDays(due, today: today)}';

    return ListTile(
      onTap: () => context.go(AppRoutes.plan),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.brandSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.receipt_long_outlined, color: colors.link),
      ),
      title: Text(bill.name, style: theme.textTheme.titleMedium),
      subtitle: Text(
        when,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: overdue ? colors.link : colors.textMuted,
        ),
      ),
      trailing: Text(
        _plain(context, bill.amountMinor),
        style: AppTypography.amount(
          size: 18,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
