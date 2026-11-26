import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/plan/bills_calendar.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../settings/application/week_start_provider.dart';
import '../application/budget_alert_providers.dart';
import '../application/plan_providers.dart';
import 'plan_item_sheet.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `Wed 25 Nov`.
String _dayTitle(CalendarDate date) =>
    '${weekdayName(date).substring(0, 3)} ${shortDate(date)}';

/// Opens Plan on this month's bills calendar, scrolled to it, as Home's
/// "Coming up" does.
void openBillsCalendar(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  container
      .read(planMonthProvider.notifier)
      .show(container.read(currentMonthProvider));
  container.read(billsDayProvider.notifier).choose(null);
  container.read(billsViewProvider.notifier).show(BillsView.calendar);
  context.go(AppRoutes.plan);
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => container.read(billsFocusProvider.notifier).request(),
  );
}

/// Plan's bills as a month grid, from the day the week starts on, and what is due on the
/// chosen day under it.
class BillsCalendarView extends ConsumerWidget {
  const BillsCalendarView({required this.month, super.key});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final chosen = ref.watch(billsDayProvider);
    final day = chosen != null && month.contains(chosen)
        ? chosen
        : month.contains(today)
        ? today
        : month.firstDay;
    final bills = ref.watch(billsMonthProvider(month));
    return switch (bills) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MonthGrid(bills: value, today: today, chosen: day),
          _DayList(bills: value, day: day, today: today),
        ],
      ),
      AsyncError() => ErrorView(
        'The calendar could not load.',
        onRetry: () => ref.invalidate(billsMonthProvider(month)),
      ),
      _ => const LoadingView(inList: true),
    };
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.bills,
    required this.today,
    required this.chosen,
  });

  final BillsMonth bills;
  final CalendarDate today;
  final CalendarDate chosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final month = bills.month;
    final firstDay = ref.watch(weekStartsOnProvider);
    final days = calendarGridDays(month, weekStartsOn: firstDay);
    final small = theme.textTheme.bodySmall!.copyWith(
      color: colors.mutedSmall(theme.colorScheme.onSurface),
    );

    Widget dot(Color colour) => Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );

    Widget cell(CalendarDate date) {
      final inMonth = month.contains(date);
      final due = bills.stillDueOn(date);
      final selected = inMonth && date == chosen;
      final isToday = date == today;
      final ink = selected
          ? colors.link
          : inMonth
          ? theme.colorScheme.onSurface
          : colors.textMuted.withValues(alpha: 0.6);
      final label = [
        longDate(date),
        if (isToday) 'today',
        if (due == true) 'something due',
        if (due == false) 'all paid',
      ].join(', ');
      return Semantics(
        button: inMonth,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          key: Key('bills-day-${date.day}${inMonth ? '' : '-out'}'),
          customBorder: const CircleBorder(),
          onTap: inMonth
              ? () => ref.read(billsDayProvider.notifier).choose(date)
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Layout.minTouch),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: ink,
                    fontWeight: selected || isToday ? FontWeight.w600 : null,
                    decoration: isToday ? TextDecoration.underline : null,
                    decorationColor: ink,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 5,
                  child: switch (due) {
                    true => dot(
                      inMonth ? theme.colorScheme.onSurface : colors.textMuted,
                    ),
                    false => dot(colors.textMuted),
                    null => null,
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      key: const Key('bills-calendar'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Layout.cardPadding,
          8,
          Layout.cardPadding,
          Layout.cardPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${monthName(month)} ${month.year}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _show(ref, month.previous),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _show(ref, month.next),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (final w in [
                    for (var i = 0; i < 7; i++)
                      _weekdays[(firstDay - 1 + i) % 7],
                  ])
                    Expanded(
                      // Shrinks rather than break a day's name at large
                      // text: seven columns share a phone's width.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(w, style: small),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            for (var week = 0; week < days.length; week += 7)
              Row(
                children: [
                  for (final date in days.sublist(week, week + 7))
                    Expanded(child: cell(date)),
                ],
              ),
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Key(dot(theme.colorScheme.onSurface), 'Something due'),
                  _Key(dot(colors.textMuted), 'All paid'),
                  if (month.contains(today))
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${today.day}',
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' is today'),
                        ],
                      ),
                      style: small,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _show(WidgetRef ref, YearMonth month) {
    ref.read(billsDayProvider.notifier).choose(null);
    ref.read(planMonthProvider.notifier).show(month);
  }
}

class _Key extends StatelessWidget {
  const _Key(this.mark, this.text);

  final Widget mark;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall!.copyWith(
            color: PesaColors.of(context)
                .mutedSmall(theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.bills, required this.day, required this.today});

  final BillsMonth bills;
  final CalendarDate day;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final due = bills.on(day);
    final ahead = today.daysUntil(day);
    final when = ahead > 0 && due.any((b) => b.state != CalendarBillState.paid)
        ? relativeDays(day, today: today)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          _dayTitle(day),
          trailing: when == null
              ? null
              : Text(
                  '${when[0].toUpperCase()}${when.substring(1)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        if (due.isEmpty)
          const EmptyNote('Nothing is due on this day.')
        else
          Card(
            key: const Key('bills-day-list'),
            child: Column(
              children: [
                for (final (i, bill) in due.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _DueRow(bill, today: today),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// How a calendar bill stands, such as `Unpaid`, `4 days late` or
/// `Paid 5 Nov`.
String billStateLabel(CalendarBill bill, {required CalendarDate today}) =>
    switch (bill.state) {
      CalendarBillState.unpaid => 'Unpaid',
      CalendarBillState.late => relativeDays(bill.date, today: today),
      CalendarBillState.paid => switch (bill.paidOn) {
        final on? => 'Paid ${shortDate(on)}',
        null => 'Paid',
      },
    };

class _DueRow extends StatelessWidget {
  const _DueRow(this.bill, {required this.today});

  final CalendarBill bill;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final stateColour = switch (bill.state) {
      CalendarBillState.unpaid => colors.mutedSmall(
        theme.colorScheme.onSurface,
      ),
      CalendarBillState.late => colors.warning,
      CalendarBillState.paid => colors.successText,
    };
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.name, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(bill.detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FigureText(
                  shownMoney(context, bill.amountMinor),
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  billStateLabel(bill, today: today),
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: stateColour,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    switch (bill.source) {
      case CalendarBillSource.plan:
        showBillSheet(context, bill);
      case CalendarBillSource.subscription:
        context.push(AppRoutes.subscriptions);
      case CalendarBillSource.debt:
        context.go(AppRoutes.debts);
    }
  }
}

/// One bill from Plan: what it is, what is paid, and a way to edit it.
/// Calendar bills from Plan are dated, so recurring: a payment marks them
/// paid, as in the list.
Future<void> showBillSheet(BuildContext context, CalendarBill bill) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => _BillSheet(bill),
    );

class _BillSheet extends StatelessWidget {
  const _BillSheet(this.bill);

  final CalendarBill bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = bill.line!;
    final edit = OutlinedButton(
      onPressed: () {
        Navigator.of(context).pop();
        showPlanItemSheet(context, month: bill.date.yearMonth, line: line);
      },
      child: const Text('Edit'),
    );
    return SheetBody(
      title: bill.name,
      subtitle: 'Due ${_dayTitle(bill.date)} · from Plan',
      children: [
        Card(
          child: Column(
            children: [
              LabelValueRow(
                label: 'Amount',
                value: shownMoney(context, bill.amountMinor),
              ),
              const Divider(height: 1),
              LabelValueRow(
                label: 'Paid so far',
                value: shownMoney(context, bill.paidMinor),
              ),
              const Divider(height: 1),
              LabelValueRow(
                label: 'Category',
                value: bill.categoryName ?? 'Uncategorised',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'The same item as in the list. Paying it by M-Pesa marks it paid '
          'by itself.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        edit,
      ],
    );
  }
}
