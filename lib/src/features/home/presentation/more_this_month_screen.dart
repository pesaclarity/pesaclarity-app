import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/budget/until_next_money.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/application/balances_providers.dart';
import '../../balances/presentation/balance_text.dart';
import '../../balances/presentation/balance_warning.dart';
import '../../balances/presentation/on_hand_sheet.dart';
import '../../currency/application/currency_controller.dart';
import '../../goals/presentation/goals_aside_text.dart';
import '../../income/application/income_providers.dart';
import '../../insights/presentation/health_colors.dart';
import '../../spaces/application/money_between_spaces_providers.dart';
import '../application/cash_flow_forecast_provider.dart';
import '../application/health_index_provider.dart';
import '../application/home_safe_provider.dart';

/// A red card's figure: the one place the currency code shows.
String _kes(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: true);

/// Every other amount: a plain number in the base currency.
String _plain(BuildContext context, int minor) => shownMoney(context, minor);

/// Insights › Your month: safe to spend with what
/// it is made of (until the next money, or the month's plan), On hand or
/// what is left this month, the runway at this pace, the month-end
/// forecast and financial health. These were Home's cards before Home
/// became simpler; nothing about them changed.
class MoreThisMonthScreen extends ConsumerWidget {
  const MoreThisMonthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final safe = ref.watch(homeSafeProvider);
    final safeToSpend = safe.monthly;
    final untilNext = safe.untilNext;
    final health = ref.watch(healthIndexProvider).value;
    final forecast = ref.watch(cashFlowForecastProvider).value;
    // How much of On hand is another space's (decision 0027).
    final heldBy = untilNext == null
        ? null
        : ref.watch(moneyBetweenSpacesProvider).value?.heldBySpace;
    final held = heldBy == null || heldBy.isEmpty
        ? null
        : heldLine(
            heldBy,
            ref.watch(spaceNamesProvider),
            (minor) => shownMoney(context, minor, withCurrency: true),
          );
    // What goals kept aside take off On hand (see GoalsAside).
    final onHandParts = ref.watch(onHandProvider).value;
    final goalsWanted = onHandParts?.goalsWantedMinor ?? 0;
    final goalsAside = onHandParts?.goalsAsideMinor ?? 0;
    final goalsNote = goalsWanted <= 0
        ? null
        : goalsAside < goalsWanted
        ? GoalsAsideText.stillAside(
            _plain(context, goalsAside),
            _plain(context, goalsWanted),
          )
        : GoalsAsideText.setAsideLine(_plain(context, goalsWanted));
    final currency = ref.watch(currencyControllerProvider).value;
    final now = ref.watch(clockProvider)();
    // The second currency under the main figure, when there is a rate.
    String? second(int minor) {
      final money = currency?.inSecondary(minor, now);
      if (money == null) return null;
      final shown = shownMoney(
        context,
        money.minorUnits,
        currency: money.currency,
        withCurrency: true,
      );
      return '≈ $shown';
    }

    void openActivity(ActivityFilter filter) =>
        context.go(AppRoutes.activityWith(filter));
    final thisMonth = ActivityFilter(from: today.yearMonth.firstDay, to: today);
    final paceWindow = ActivityFilter(
      type: ActivityType.spending,
      from: today.addDays(-paceWindowDays),
      to: today,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your month'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: AmountsHiddenScope(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (safeToSpend == null && untilNext != null)
              _UntilNextMoneyCard(
                untilNext,
                secondFigure: second(untilNext.leftTodayMinor),
                rainyDayMinor:
                    ref.watch(rainyDayFundProvider).value?.balanceMinor ?? 0,
                goalsAsideMinor: goalsAside,
                goalsKept: goalsWanted > 0,
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
                secondFigure: second(safeToSpend.leftTodayMinor),
                nextIncome: forecast?.nextIncome,
                onTap: () => openActivity(
                  thisMonth.copyWith(type: ActivityType.dayToDay),
                ),
              ),
            const BalanceWarningLine(),
            const SizedBox(height: 12),
            FigureRow(
              children: [
                if (untilNext != null)
                  FigureTile(
                    key: const Key('home-on-hand'),
                    label: 'On hand',
                    value: _plain(context, untilNext.onHandMinor),
                    note: held == null && goalsNote == null
                        ? second(untilNext.onHandMinor)
                        : [?held, ?goalsNote].join(' · '),
                    belowZero: untilNext.onHandMinor < 0,
                    onTap: () => showOnHandSheet(context),
                  )
                else if (safeToSpend == null)
                  const FigureTile(
                    label: 'Left this month',
                    value: 'Soon',
                    note: 'Shows once Plan has a budget',
                  )
                else
                  FigureTile(
                    label: safeToSpend.payCycle
                        ? 'Left this pay cycle'
                        : 'Left this month',
                    value: _plain(context, safeToSpend.leftThisMonthMinor),
                    belowZero: safeToSpend.leftThisMonthMinor < 0,
                    onTap: () => openActivity(
                      ActivityFilter(
                        from: safeToSpend.periodFirst ?? thisMonth.from,
                        to: today,
                        type: ActivityType.dayToDay,
                      ),
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
              _ForecastCard(forecast, onTap: () => openActivity(paceWindow)),
            ],
            if (health != null) ...[
              const SizedBox(height: 12),
              _HealthIndexCard(
                health,
                onTap: () => context.go(AppRoutes.insights),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How long the money lasts at this pace, or null until there is a pace.
String? _runwayLabel(CashFlowForecast? forecast) {
  final days = forecast?.runwayDays;
  if (days == null) return null;
  if (days <= 0) return 'Today';
  return days == 1 ? '1 day' : '$days days';
}

class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard(
    this.result, {
    required this.onTap,
    this.nextIncome,
    this.secondFigure,
  });

  final SafeToSpend result;
  final String? secondFigure;
  final ScheduledFlow? nextIncome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = result.today;
    final String detail;
    if (result.nothingFreeAfterGoals) {
      detail = GoalsAsideText.nothingFree;
    } else if (result.nothingOnHand) {
      detail = BalanceText.belowZero;
    } else if (result.isBudgetUsedUp) {
      detail = result.payCycle
          ? 'This pay cycle\'s day-to-day budget is used up'
          : 'This month\'s day-to-day budget is used up';
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
      secondFigure: secondFigure,
      caption: '$detail$payday',
      footer: HeroProgress(
        value: used,
        label:
            '${(used * 100).round()}% of this '
            '${result.payCycle ? 'pay cycle' : 'month'}\'s spending plan used',
      ),
      // The figure is already masked while hidden: keep the eye to show it.
      showEye: true,
      // Below zero is the one sign of trouble: a danger-coloured figure.
      belowZero: (result.onHandMinor ?? 0) < 0,
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
    this.goalsAsideMinor = 0,
    this.goalsKept = false,
    this.secondFigure,
  });

  final UntilNextMoney result;
  final String? secondFigure;

  /// Set aside in the fund, already out of [UntilNextMoney.onHandMinor].
  final int rainyDayMinor;

  /// Set aside for goals, already out of [UntilNextMoney.onHandMinor].
  final int goalsAsideMinor;

  /// Whether any goal is kept aside: with nothing free, the card says the
  /// goals took it.
  final bool goalsKept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = result.nextMoney;
    final lasts = result.lastsUntil;
    final String when;
    if (result.belowZero) {
      when = result.fulizaOwedMinor > 0
          ? BalanceText.belowZeroFuliza
          : BalanceText.belowZero;
    } else if (goalsKept && result.onHandMinor == 0) {
      when = GoalsAsideText.nothingFree;
    } else if (result.nothingSafe) {
      when = BalanceText.billsTakeIt;
    } else if (result.overTodayMinor > 0) {
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
      if (goalsAsideMinor > 0)
        ' · ${GoalsAsideText.setAsideLine(_plain(context, goalsAsideMinor))}',
    ].join();

    return HeroFigureCard(
      key: const Key('until-next-money'),
      label: result.pinned ? 'Your plan for today' : 'Safe to spend today',
      figure: _kes(context, result.leftTodayMinor),
      secondFigure: secondFigure,
      caption: '$when\n$onHand$setAside',
      showEye: true,
      belowZero: result.belowZero,
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
    final figure = AppTypography.tileFigure(theme.colorScheme.onSurface);
    // The ring holds three digits at the type scale's tile size and grows
    // with the text size, rather than shrinking the score to fit.
    final ring = math.max(
      _healthRingMin,
      MediaQuery.textScalerOf(context).scale(figure.fontSize!) * 2 +
          2 * (_healthRingStroke + 6),
    );

    final healthRing = SizedBox.square(
      dimension: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: math.min(index.score, 100) / 100,
              strokeWidth: _healthRingStroke,
              // The band's colour on a neutral track: brand red
              // is kept for actions.
              color: healthBandColor(context, index.band),
              backgroundColor: colors.border,
            ),
          ),
          Text('${index.score}', style: figure),
        ],
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Financial health · ${index.band.label}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          headline,
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
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
    );
    final chevron = Icon(Icons.chevron_right, color: colors.textMuted);
    // With very large text the ring leaves too little room beside it for a
    // long word, so it goes above the words instead.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.75;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    healthRing,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: details),
                        chevron,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    healthRing,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                    chevron,
                  ],
                ),
        ),
      ),
    );
  }
}

const _healthRingMin = 64.0;
const _healthRingStroke = 6.0;

String _points(int n) => n == 1 ? '1 point' : '$n points';
