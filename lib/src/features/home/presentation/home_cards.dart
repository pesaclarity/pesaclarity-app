import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/budget/until_next_money.dart';
import '../../../domain/income/make_it_last.dart';
import '../../../domain/plan/upcoming_bills.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../income/application/income_providers.dart';
import '../../income/presentation/make_it_last_sheet.dart';
import '../../income/presentation/what_was_this_sheet.dart';
import '../../plan/presentation/bills_calendar_view.dart';

/// Cards Home shares between a personal space and the others.

/// Bills shown under Coming up before "See all".
const homeBillsShown = 3;

/// Every other amount: a plain number in the base currency.
String _plain(BuildContext context, int minor) => shownMoney(context, minor);

/// `Fri 14 Nov`.
String _dayLabel(CalendarDate date) =>
    '${weekdayName(date).substring(0, 3)} ${shortDate(date)}';

/// Money in from people whose money has meant different things.
class WhatWasThisCard extends ConsumerWidget {
  const WhatWasThisCard({super.key});

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
class MakeItLastCard extends ConsumerWidget {
  const MakeItLastCard(this.plan, {required this.today, super.key});

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
class WeekByWeekCard extends ConsumerWidget {
  const WeekByWeekCard({super.key});

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

/// Coming up: the next bills, at most [homeBillsShown], with the calendar
/// and Plan.
class HomeComingUp extends StatelessWidget {
  const HomeComingUp({required this.bills, required this.today, super.key});

  final List<UpcomingBill> bills;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final shown = bills.take(homeBillsShown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Coming up',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillButton(
                key: const Key('home-bills-calendar'),
                label: 'Calendar',
                onPressed: () => openBillsCalendar(context),
              ),
              PillButton(
                label: 'See all',
                onPressed: () => context.go(AppRoutes.plan),
              ),
            ],
          ),
        ),
        Card(
          key: const Key('home-coming-up'),
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

    return ValueTile(
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
