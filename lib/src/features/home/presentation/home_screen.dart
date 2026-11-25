import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/perf/startup_timeline.dart';
import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_summary.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../app_status/presentation/app_notice_cards.dart';
import '../../ask/presentation/ask_entry.dart';
import '../../business_insights/application/business_report_providers.dart';
import '../../hours/application/hours_providers.dart';
import '../../hours/presentation/log_hours_sheet.dart';
import '../../income/application/income_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../sales/presentation/waiting_payments_card.dart';
import '../../sharing/presentation/group_sync_widgets.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../spaces/presentation/business_setup_card.dart';
import '../../spaces/presentation/restore_check_card.dart';
import '../../spaces/presentation/shared_line_card.dart';
import '../../spaces/presentation/spaces_sheet.dart';
import '../application/cash_flow_forecast_provider.dart';
import '../application/health_index_provider.dart';
import '../application/safe_to_spend_provider.dart';
import '../application/upcoming_bills_provider.dart';
import 'add_menu.dart';
import 'cash_below_zero_card.dart';
import 'home_cards.dart';
import 'not_yet_sorted_card.dart';
import 'personal_home.dart';

/// A red card's figure: the one place the currency code shows.
String _kes(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: true);

/// Every other amount: a plain number in the base currency.
String _plain(BuildContext context, int minor) => shownMoney(context, minor);

/// The startup phase Home marks once its cards show their numbers.
const homeShownPhase = 'home data shown';

/// Marks startup's [homeShownPhase] once Home's main cards have loaded,
/// after the frame that shows them (see [StartupTimeline]).
void _markShown(WidgetRef ref) {
  if (!StartupTimeline.waitsFor(homeShownPhase)) return;
  final loading = [
    ref.watch(safeToSpendTodayProvider),
    ref.watch(healthIndexProvider),
    ref.watch(cashFlowForecastProvider),
    ref.watch(upcomingBillsProvider),
  ].any((value) => value.isLoading);
  if (loading) return;
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => StartupTimeline.mark(homeShownPhase),
  );
}

/// Home tab: how am I doing today?
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final sources =
        ref.watch(incomeSourcesProvider).value ?? const IncomeSources({});
    final bills = ref.watch(upcomingBillsProvider).value ?? const [];

    _markShown(ref);
    final space = ref.watch(activeSpaceProvider);
    final isBusiness = space.kind == SpaceKind.business;
    // Products and both lead with today's sales; services with profit.
    final sellsProducts =
        isBusiness &&
        ref.watch(businessSetupProvider).value?.sells != BusinessSells.services;

    void openActivity(ActivityFilter filter) =>
        context.go(AppRoutes.activityWith(filter));

    final thisMonth = ActivityFilter(from: today.yearMonth.firstDay, to: today);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AmountsHiddenScope(
          child: AskBarScope(
            builder: (context, bottomPadding) => GroupSyncRefresh(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
                children: [
                  _Header(today: today),
                  const SizedBox(height: 20),
                  if (space.kind != SpaceKind.personal) ...[
                    if (sellsProducts) ...[
                      const _SalesTodayCard(),
                      const SizedBox(height: 12),
                      const RestoreCheckCard(),
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
                    const AppNoticeCards(),
                    if (!sellsProducts) const RestoreCheckCard(),
                    if (isBusiness && !sellsProducts) ...[
                      const _QuickButtons(services: true),
                      const SizedBox(height: 12),
                      const _HoursCards(),
                      const WaitingPaymentsCard(),
                    ],
                    if (space.kind == SpaceKind.business)
                      const BusinessSetupCard(),
                    const SharedLineCard(),
                    const CashBelowZeroCard(),
                    const NotYetSortedCard(),
                    const WhatWasThisCard(),
                    if (sources.irregular) const WeekByWeekCard(),
                    HomeComingUp(bills: bills, today: today),
                  ] else
                    PersonalHome(today: today),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
                // A long name shrinks to fit under large text rather than
                // fading out at the chip's edge; the chip keeps its height.
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(space.name),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ),
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
                header: true,
                // A business calls its first tab Today.
                child: Text(
                  space.kind == SpaceKind.business ? 'Today' : 'Home',
                  style: theme.textTheme.headlineLarge,
                ),
              ),
            ],
          ),
        ),
        const AskHomeButton(),
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
      // No amount yet, so no eye to hide one.
      return const HeroFigureCard(
        key: Key('sales-today'),
        label: 'Sales today',
        caption: 'Sales show here as you sell.',
        showEye: false,
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
