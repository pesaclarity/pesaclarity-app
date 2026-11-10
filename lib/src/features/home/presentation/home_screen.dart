import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/budget/until_next_money.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/income/make_it_last.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/plan/upcoming_bills.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_summary.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../business_insights/application/business_report_providers.dart';
import '../../hours/application/hours_providers.dart';
import '../../hours/presentation/log_hours_sheet.dart';
import '../../income/application/income_providers.dart';
import '../../income/presentation/make_it_last_sheet.dart';
import '../../income/presentation/what_was_this_sheet.dart';
import '../../review/application/review_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../sales/presentation/waiting_payments_card.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../spaces/presentation/business_setup_card.dart';
import '../../spaces/presentation/shared_line_card.dart';
import '../../spaces/presentation/spaces_sheet.dart';
import '../../support/presentation/support_card.dart';
import '../application/cash_flow_forecast_provider.dart';
import '../application/health_index_provider.dart';
import '../application/safe_to_spend_provider.dart';
import '../application/upcoming_bills_provider.dart';
import 'add_menu.dart';

/// Bills shown under Coming up before "See all".
const _billsShown = 3;

/// A red card's figure: the one place the currency code shows.
String _kes(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: true);

/// Every other amount: a plain number in the base currency.
String _plain(BuildContext context, int minor) => shownMoney(context, minor);

/// Home tab: how am I doing today?
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final monthlySafe = ref.watch(safeToSpendTodayProvider).value;
    final sources =
        ref.watch(incomeSourcesProvider).value ?? const IncomeSources({});
    // A salary alone keeps the monthly figure; everyone else plans until
    // the next money.
    final safeToSpend =
        monthlySafe != null &&
            monthlyPlanFits(sources, hasBudget: monthlySafe.budgetMinor > 0)
        ? monthlySafe
        : null;
    final untilNext = safeToSpend == null
        ? ref.watch(untilNextMoneyProvider).value
        : null;
    final health = ref.watch(healthIndexProvider).value;
    final forecast = ref.watch(cashFlowForecastProvider).value;
    final bills = ref.watch(upcomingBillsProvider).value ?? const [];
    final space = ref.watch(activeSpaceProvider);
    final isBusiness = space.kind == SpaceKind.business;
    // Products and both lead with today's sales; services with profit.
    final sellsProducts =
        isBusiness &&
        ref.watch(businessSetupProvider).value?.sells != BusinessSells.services;

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
        child: AmountsHiddenScope(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              _Header(today: today),
              const SizedBox(height: 20),
              if (space.kind != SpaceKind.personal) ...[
                if (sellsProducts) ...[
                  const _SalesTodayCard(),
                  const SizedBox(height: 12),
                  const _QuickButtons(services: false),
                  const SizedBox(height: 12),
                  const WaitingPaymentsCard(),
                ],
                _SpaceSummaryCard(
                  _summaryFor(ref, isBusiness: isBusiness, today: today),
                  kind: space.kind,
                  compact: sellsProducts,
                  onTap: () => openActivity(thisMonth),
                ),
                const SizedBox(height: 12),
                if (isBusiness && !sellsProducts) ...[
                  const _QuickButtons(services: true),
                  const SizedBox(height: 12),
                  const _HoursCards(),
                  const WaitingPaymentsCard(),
                ],
                if (space.kind == SpaceKind.business) const BusinessSetupCard(),
                const SharedLineCard(),
                const _ReviewCard(),
                const _WhatWasThisCard(),
                if (sources.irregular) const _WeekCard(),
                const SizedBox(height: 12),
                _ComingUp(bills: bills, today: today),
              ] else ...[
                if (safeToSpend == null && untilNext != null)
                  _UntilNextMoneyCard(
                    untilNext,
                    rainyDayMinor:
                        ref.watch(rainyDayFundProvider).value?.balanceMinor ??
                        0,
                    onTap: () => openActivity(
                      ActivityFilter(
                        type: ActivityType.spending,
                        from: today,
                        to: today,
                      ),
                    ),
                  )
                else if (safeToSpend == null)
                  const HeroFigureCard(
                    label: 'Safe to spend today',
                    caption:
                        'Shows once your messages have been read and Plan has '
                        'a day-to-day budget.',
                    showEye: true,
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
                SupportHomeCard(
                  moneyTight: _moneyTight(safeToSpend, untilNext, forecast),
                ),
                const _ReviewCard(),
                const _WhatWasThisCard(),
                if (untilNext != null) _MoneyInCard(untilNext, today: today),
                if (untilNext != null && sources.irregular) const _WeekCard(),
                FigureRow(
                  children: [
                    if (untilNext != null)
                      FigureTile(
                        key: const Key('home-on-hand'),
                        label: 'On hand',
                        value: _plain(context, untilNext.onHandMinor),
                      )
                    else if (safeToSpend == null)
                      const FigureTile(
                        label: 'Left this month',
                        value: 'Soon',
                        note: 'Shows once Plan has a budget',
                      )
                    else
                      FigureTile(
                        label: 'Left this month',
                        value: _plain(context, safeToSpend.leftThisMonthMinor),
                        onTap: () => openActivity(
                          thisMonth.copyWith(type: ActivityType.dayToDay),
                        ),
                      ),
                    if (_runwayLabel(forecast) case final runway?)
                      FigureTile(
                        label: 'Runway at this pace',
                        value: runway,
                        onTap: () => openActivity(paceWindow),
                      )
                    else
                      const FigureTile(
                        label: 'Runway at this pace',
                        value: 'Soon',
                        note: 'Shows after two weeks of records',
                      ),
                  ],
                ),
                if (forecast != null) ...[
                  const SizedBox(height: 12),
                  _ForecastCard(
                    forecast,
                    onTap: () => openActivity(paceWindow),
                  ),
                ],
                if (health != null) ...[
                  const SizedBox(height: 12),
                  _HealthIndexCard(
                    health,
                    onTap: () => context.go(AppRoutes.insights),
                  ),
                ],
                const SizedBox(height: 24),
                _ComingUp(bills: bills, today: today),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's money is spent, the plan is used up or a payment may not go
/// through: Home never asks for a gift then.
bool _moneyTight(
  SafeToSpend? safeToSpend,
  UntilNextMoney? untilNext,
  CashFlowForecast? forecast,
) =>
    (safeToSpend != null &&
        (safeToSpend.isBudgetUsedUp || safeToSpend.leftTodayMinor <= 0)) ||
    (untilNext != null &&
        (untilNext.runsOutEarly || untilNext.leftTodayMinor <= 0)) ||
    (forecast?.failingCharges.isNotEmpty ?? false);

/// How long the money lasts at this pace, or null until there is a pace.
String? _runwayLabel(CashFlowForecast? forecast) {
  final days = forecast?.runwayDays;
  if (days == null) return null;
  if (days <= 0) return 'Today';
  return days == 1 ? '1 day' : '$days days';
}

class _Header extends ConsumerWidget {
  const _Header({required this.today});

  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final space = ref.watch(activeSpaceProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActionChip(
                key: const Key('home-space'),
                tooltip: 'Switch space',
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(space.name),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
                onPressed: () => showSpaces(context),
              ),
              const SizedBox(height: 4),
              Text(
                longDate(today),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              Semantics(
                identifier: SemanticIds.titleHome,
                // A business calls its first tab Today.
                child: Text(
                  space.kind == SpaceKind.business ? 'Today' : 'Home',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
            ],
          ),
        ),
        // An outlined circle: red stays for the + and the lead card.
        Semantics(
          identifier: SemanticIds.homeProfile,
          child: IconButton.outlined(
            tooltip: 'Profile',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.onSurface,
              side: BorderSide(color: colors.border),
            ),
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
    final today = result.today;
    final String detail;
    if (result.isBudgetUsedUp) {
      detail = 'This month\'s day-to-day budget is used up';
    } else if (result.overTodayMinor > 0) {
      detail = '${_plain(context, result.overTodayMinor)} over today\'s limit';
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

    return HeroFigureCard(
      label: 'Safe to spend today · ${today.isWeekend ? 'Weekend' : 'Weekday'}',
      figure: _kes(context, result.leftTodayMinor),
      caption: '$detail$payday',
      footer: HeroProgress(
        value: used,
        label: '${(used * 100).round()}% of this month\'s spending plan used',
      ),
      // The figure is already masked while hidden: keep the eye to show it.
      showEye: true,
      onTap: onTap,
    );
  }
}

/// Safe to spend for people without a payday: what is on hand, spread
/// until the next money.
class _UntilNextMoneyCard extends StatelessWidget {
  const _UntilNextMoneyCard(
    this.result, {
    required this.onTap,
    this.rainyDayMinor = 0,
  });

  final UntilNextMoney result;

  /// Set aside in the fund, already out of [UntilNextMoney.onHandMinor].
  final int rainyDayMinor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = result.nextMoney;
    final lasts = result.lastsUntil;
    final String when;
    if (result.overTodayMinor > 0) {
      when = "${_plain(context, result.overTodayMinor)} over today's amount";
    } else if (result.fromUsualDay) {
      when = result.today.isWeekend
          ? 'What you usually spend on a weekend day'
          : 'What you usually spend on a weekday';
    } else if (result.basis == NextMoneyBasis.rhythm && next != null) {
      when = 'Until about ${_dayLabel(next)}, when money usually comes';
    } else if (result.basis == NextMoneyBasis.noDate) {
      when = lasts == null
          ? 'Spread over what you have'
          : 'Lasts until about ${_dayLabel(lasts)} at this pace';
    } else {
      when = 'For the next ${result.days} days';
    }
    final onHand = '${_plain(context, result.onHandMinor)} on hand';
    final setAside = [
      if (result.billsMinor > 0)
        ' · ${_plain(context, result.billsMinor)} for bills',
      if (rainyDayMinor > 0)
        ' · ${_plain(context, rainyDayMinor)} in your rainy day fund',
    ].join();

    return HeroFigureCard(
      key: const Key('until-next-money'),
      label: result.pinned ? 'Your plan for today' : 'Safe to spend today',
      figure: _kes(context, result.leftTodayMinor),
      caption: '$when\n$onHand$setAside',
      showEye: true,
      onTap: onTap,
    );
  }
}

/// `Fri 14 Nov`.
String _dayLabel(CalendarDate date) =>
    '${weekdayName(date).substring(0, 3)} ${shortDate(date)}';

String _daysTo(int days) => switch (days) {
  <= 0 => '0 days',
  1 => '1 day',
  _ => '$days days',
};

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
    String money(int minor) =>
        shownMoney(context, minor, currency: forecast.currency);
    String when(CalendarDate date) =>
        date == forecast.today ? 'today' : 'on the ${ordinalDay(date.day)}';

    final zero = forecast.zeroDate;
    final title = zero != null
        ? 'At this pace you hit zero ${when(zero)}.'
        : 'At this pace you end the month with '
              '${money(forecast.monthEndBalanceMinor)}.';
    // Every upcoming payment that may not go through, one line each.
    final warnings = [
      for (final c in forecast.failingCharges)
        'Your ${c.name} payment of ${money(c.amountMinor)} ${when(c.date)} '
            'may not go through. You would be ${money(c.shortMinor)} short.',
    ];

    return Card(
      child: InkWell(
        key: const Key('home-forecast'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                zero != null ? Icons.trending_down : Icons.trending_flat,
                color: zero != null ? colors.warning : colors.successText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    for (final warning in warnings) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: colors.warning,
                            ),
                          ),
                          const SizedBox(width: 8),
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
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The financial health score, its band, the change on the month before,
/// and the weakest part with what would help most.
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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
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
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${index.score}',
                          style: AppTypography.tileFigure(
                            theme.colorScheme.onSurface,
                          ),
                        ),
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
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headline,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Weakest: ${action.indicator.label.toLowerCase()}. '
                        '${action.message}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
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
        // The space above comes from the cards before it.
        SectionTitle(
          'Coming up',
          padding: const EdgeInsets.only(bottom: 8),
          action: PillButton(
            label: 'See all',
            onPressed: () => context.go(AppRoutes.plan),
          ),
        ),
        Card(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Layout.cardPadding),
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
                      if (i > 0) const Divider(height: 1),
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
      leading: const IconBadge(Icons.receipt_long_outlined),
      title: Text(bill.name, style: theme.textTheme.titleMedium),
      subtitle: Text(
        when,
        style: theme.textTheme.bodyMedium!.copyWith(
          color: overdue ? colors.warning : colors.textMuted,
        ),
      ),
      trailing: Text(
        _plain(context, bill.amountMinor),
        style: AppTypography.rowAmount(theme.colorScheme.onSurface),
      ),
    );
  }
}

/// "3 messages to check", while the review inbox holds any.
class _ReviewCard extends ConsumerWidget {
  const _ReviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingReviewProvider).value?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-review'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(
            count == 1 ? '1 message to check' : '$count messages to check',
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => context.push(AppRoutes.review),
        ),
      ),
    );
  }
}

/// Money in from people whose money has meant different things.
class _WhatWasThisCard extends ConsumerWidget {
  const _WhatWasThisCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(purposeQueueProvider).value ?? const [];
    if (queue.isEmpty) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    final first = queue.first;
    final from = first.payeeName ?? first.counterpartyName ?? 'someone';
    final amount = shownMoney(
      context,
      first.amountMinor,
      currency: first.currency,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-what-was-this'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: const Text('What was this?'),
          subtitle: Text(
            [
              '$amount from $from',
              if (queue.length > 1) '${queue.length - 1} more',
            ].join(' · '),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showWhatWasThis(
            context,
            transactionId: first.id,
            payeeName: from,
            amountMinor: first.amountMinor,
            currency: first.currency,
          ),
        ),
      ),
    );
  }
}

/// Money that just arrived, with a plan to make it last.
class _MoneyInCard extends ConsumerWidget {
  const _MoneyInCard(this.plan, {required this.today});

  final UntilNextMoney plan;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrival = ref.watch(latestArrivalProvider).value;
    final pin = ref.watch(makeItLastProvider).value;
    if (arrival == null ||
        today.daysUntil(arrival.date) < -makeItLastOfferDays ||
        (pin != null && pin.arrivalId == arrival.id)) {
      return const SizedBox.shrink();
    }
    final from = arrival.payeeName ?? arrival.counterpartyName;
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-money-in'),
          title: const Text('Make it last'),
          subtitle: Text(
            [
              '${_plain(context, arrival.amountMinor)} came in',
              if (from != null) 'from $from',
              '· until ${_dayLabel(plan.lastDay)}',
            ].join(' '),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showMakeItLast(
            context,
            arrivalId: arrival.id,
            arrivalMinor: arrival.amountMinor,
            from: from ?? 'someone',
            plan: plan,
          ),
        ),
      ),
    );
  }
}

/// Business and gigs: this week so far, opening week by week.
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(weekByWeekProvider).value;
    if (plan == null) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    final week = plan.thisWeek;
    final add = plan.suggestAddMinor;
    final take = plan.suggestTakeMinor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-week'),
          title: Text(
            'This week · in ${_plain(context, week.inMinor)} · '
            'out ${_plain(context, week.outMinor)}',
          ),
          subtitle: Text(
            add > 0
                ? 'A good week. Put ${_plain(context, add)} in your rainy day fund?'
                : take > 0
                ? 'Your rainy day fund can cover up to ${_plain(context, take)}'
                : 'Week by week and your rainy day fund',
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => context.push(AppRoutes.weekByWeek),
        ),
      ),
    );
  }
}

/// A business's quick records on Today, two by two. Products: Bought, Got
/// paid, Paid, Close the day. Services: Got paid, Spent, Log hours, Billed.
/// Below them, More ways to record: cash in or out, pay yourself and
/// statements.
class _QuickButtons extends StatelessWidget {
  const _QuickButtons({required this.services});

  final bool services;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final buttons = services
        ? [
            _QuickButton(
              'Got paid',
              'A client pays what they owe',
              () => showGotPaidSheet(context),
            ),
            _QuickButton(
              'Spent',
              'A business cost',
              () => showBoughtSheet(context, costOnly: true),
            ),
            _QuickButton(
              'Log hours',
              'Time on a project',
              () => showLogHoursSheet(context),
            ),
            _QuickButton(
              'Billed',
              'Make an invoice',
              () => context.push(AppRoutes.billed),
            ),
          ]
        : [
            _QuickButton(
              'Bought',
              'Stock or a cost',
              () => showBoughtSheet(context),
            ),
            _QuickButton(
              'Got paid',
              'A customer pays you',
              () => showGotPaidSheet(context),
            ),
            _QuickButton(
              'Paid',
              'You pay a supplier',
              () => showPaidSheet(context),
            ),
            _QuickButton(
              'Close the day',
              'Count your cash',
              () => context.push(AppRoutes.closeDay),
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Layout.cardGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: buttons[i]),
                const SizedBox(width: Layout.cardGap),
                Expanded(child: buttons[i + 1]),
              ],
            ),
          ),
        ],
        const SizedBox(height: Layout.cardGap),
        Card(
          child: ListTile(
            key: const Key('quick-more'),
            title: const Text('More ways to record'),
            subtitle: const Text('Cash in or out, pay yourself, a statement'),
            trailing: Icon(Icons.chevron_right, color: colors.textMuted),
            onTap: () => showAddMenu(context, business: true),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton(this.title, this.subtitle, this.onTap);

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      key: Key('quick-${title.toLowerCase().replaceAll(' ', '-')}'),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today in a business that sells products: sales so far by how people
/// paid, against a usual day like it.
class _SalesTodayCard extends ConsumerWidget {
  const _SalesTodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(salesTodayProvider).value;
    final day = sales?.day;
    // Nothing sold yet today: say what will show instead of a nought.
    if (day == null || day.byWay.isEmpty) {
      return const HeroFigureCard(
        key: Key('sales-today'),
        label: 'Sales today',
        caption: 'Sales show here as you sell.',
        showEye: true,
      );
    }
    final ways = [
      for (final MapEntry(:key, :value) in day.byWay.entries)
        '${methodLabel(key)} ${_plain(context, value)}',
    ].join(' · ');
    final usual = sales!.usualMinor;
    final weekday = weekdayName(day.date);
    final compared = usual == null || day.totalMinor == 0
        ? null
        : _compared(context, day.totalMinor, usual, weekday);
    return HeroFigureCard(
      key: const Key('sales-today'),
      label: 'Sales today',
      figure: _kes(context, day.totalMinor),
      caption: [ways, ?compared].join('\n'),
      showEye: true,
    );
  }
}

/// Today against a usual day: up by a share, about the same, or what a
/// usual day sells.
String _compared(BuildContext context, int today, int usual, String weekday) {
  final percent = ((today - usual) * 100 / usual).round();
  if (percent == 0) return 'About the same as a usual $weekday';
  if (percent > 0) return 'Up $percent% on a usual $weekday';
  return 'A usual $weekday is ${_plain(context, usual)}';
}

/// The space's summary; a business takes this month's money in and costs
/// from its books, so Today and Insights show the same profit.
SpaceSummary? _summaryFor(
  WidgetRef ref, {
  required bool isBusiness,
  required CalendarDate today,
}) {
  final summary = ref.watch(spaceSummaryProvider).value;
  if (!isBusiness || summary == null) return summary;
  final pnl = ref
      .watch(businessProfitProvider(ReportPeriod.thisMonth(today)))
      .value;
  return pnl == null
      ? null
      : summary.withTotals(inMinor: pnl.incomeMinor, outMinor: pnl.costsMinor);
}

/// The top of Home for a space that is not Personal: profit for a business,
/// rental or farm, what is left for a household, a savings group's pot.
class _SpaceSummaryCard extends StatelessWidget {
  const _SpaceSummaryCard(
    this.summary, {
    required this.kind,
    required this.onTap,
    this.compact = false,
  });

  final SpaceSummary? summary;
  final SpaceKind kind;
  final VoidCallback onTap;

  /// Shown under another card that leads: a plain card, not the red one.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    if (summary == null && compact) return const SizedBox.shrink();
    if (summary == null) {
      return HeroFigureCard(
        label: kind.label,
        caption: 'Shows once this space has transactions.',
        showEye: true,
      );
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final colors = PesaColors.of(context);
    final inLabel = switch (kind) {
      SpaceKind.business || SpaceKind.farm => 'Sales',
      SpaceKind.rentalProperty => 'Rent',
      _ => 'In',
    };
    final detail = switch (kind) {
      SpaceKind.business || SpaceKind.rentalProperty || SpaceKind.farm =>
        '$inLabel ${_plain(context, summary.inMinor)} · costs '
            '${_plain(context, summary.outMinor)}',
      SpaceKind.household =>
        'In ${_plain(context, summary.inMinor)} · out '
            '${_plain(context, summary.outMinor)}'
            '${summary.payersCount > 1 ? ' · ${summary.payersCount} people '
                      'add money' : ''}',
      SpaceKind.savingsGroup => [
        summary.payersCount == 1
            ? '1 member paid in this month'
            : '${summary.payersCount} members paid in this month',
        if (summary.loansOutCount > 0)
          summary.loansOutCount == 1
              ? '1 loan out'
              : '${summary.loansOutCount} loans out',
      ].join(' · '),
      SpaceKind.personal || SpaceKind.other =>
        'In ${_plain(context, summary.inMinor)} · out '
            '${_plain(context, summary.outMinor)} this month',
    };
    final since = kind == SpaceKind.farm
        ? 'Since ${shortDate(summary.from)}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Card(
            key: const Key('space-summary'),
            child: ListTile(
              onTap: onTap,
              title: Text(summary.headline),
              subtitle: Text(detail),
              trailing: _AmountThen(_plain(context, summary.figureMinor)),
            ),
          )
        else
          HeroFigureCard(
            key: const Key('space-summary'),
            label: summary.headline,
            figure: _kes(context, summary.figureMinor),
            caption: [detail, ?since].join('\n'),
            showEye: true,
            onTap: onTap,
          ),
        if (kind.makesProfit && summary.rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final (i, row) in summary.rows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(row.name),
                    trailing: Text(
                      _plain(context, row.amountMinor),
                      style: AppTypography.rowAmount(
                        row.isIncome ? colors.successText : onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (kind.makesProfit && summary.paidYourselfMinor > 0) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('space-paid-yourself'),
            child: ListTile(
              title: const Text('Paid yourself'),
              subtitle: const Text(
                'Moved to Personal. It counts as income there, not as a '
                'cost here.',
              ),
              trailing: Text(
                _plain(context, summary.paidYourselfMinor),
                style: AppTypography.rowAmount(onSurface),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A services business's hours: this week by client and what it bills,
/// and the hours not billed yet.
class _HoursCards extends ConsumerWidget {
  const _HoursCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final week = ref.watch(weekHoursProvider(weekStart(today))).value;
    final unbilled = ref.watch(unbilledHoursProvider).value ?? const [];
    if (week == null || (week.entries.isEmpty && unbilled.isEmpty)) {
      return const SizedBox.shrink();
    }
    final unbilledMinutes = unbilled.fold(0, (sum, e) => sum + e.minutes);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          children: [
            ListTile(
              key: const Key('today-hours-week'),
              title: const Text('Hours this week'),
              subtitle: Text(
                [
                  '${hoursText(week.loggedMinutes)} h',
                  for (final MapEntry(:key, :value) in week.byClient.entries)
                    '${clientShort(key)} ${hoursText(value)}',
                ].join(' · '),
                style: muted,
              ),
              trailing: _AmountThen(_plain(context, week.amountMinor)),
              onTap: () => context.push(AppRoutes.hoursWeek),
            ),
            if (unbilledMinutes > 0) ...[
              const Divider(height: 1),
              ListTile(
                key: const Key('today-hours-unbilled'),
                title: const Text('To bill'),
                subtitle: Text('Since your last invoices', style: muted),
                trailing: _AmountThen('${hoursText(unbilledMinutes)} h'),
                onTap: () => context.push(AppRoutes.hoursWeek),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable row's figure at its end, then ›: the row's one action.
class _AmountThen extends StatelessWidget {
  const _AmountThen(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        text,
        style: AppTypography.rowAmount(Theme.of(context).colorScheme.onSurface),
      ),
      const SizedBox(width: 4),
      Icon(Icons.chevron_right, color: PesaColors.of(context).textMuted),
    ],
  );
}
