import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart'
    show ReportPeriod, periodText;
import '../../../domain/hours/hours.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../../security/application/balance_visibility.dart';
import '../application/hours_providers.dart';
import 'log_hours_sheet.dart';

/// Hours: a day's entries with what is to bill, or a week by day and by
/// project.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({this.week = false, super.key});

  /// Opens on the week.
  final bool week;

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  late var _week = widget.week;
  late CalendarDate _day = CalendarDate.local(ref.read(clockProvider)());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final from = weekStart(_day);
    final week = ref.watch(weekHoursProvider(from)).value;
    final hidden = ref.watch(balancesHiddenProvider);
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);
    final title = _week
        ? periodText(
            ReportPeriod(from, from.addDays(7), ''),
            thisYear: today.year,
          )
        : _day == today
        ? 'Today, ${shortDate(_day)}'
        : '${weekdayName(_day)} ${shortDate(_day)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Hours')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Day')),
              ButtonSegment(value: true, label: Text('Week')),
            ],
            selected: {_week},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _week = s.single),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                key: const Key('hours-back'),
                tooltip: _week ? 'Week before' : 'Day before',
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    setState(() => _day = _day.addDays(_week ? -7 : -1)),
              ),
              Expanded(
                child: Text(
                  title,
                  key: const Key('hours-title'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.outlined(
                key: const Key('hours-next'),
                tooltip: _week ? 'Week after' : 'Day after',
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    setState(() => _day = _day.addDays(_week ? 7 : 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (week == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (_week)
            ..._weekView(context, week, plain)
          else
            ..._dayView(context, DayHours(_day, week.entries)),
          if (_week && week != null && week.toBillMinutes > 0) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('hours-bill'),
              onPressed: () {
                final client = week.byClient.entries
                    .reduce((a, b) => a.value >= b.value ? a : b)
                    .key;
                context.push(AppRoutes.newInvoice(client: client));
              },
              child: const Text('Bill these hours'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('hours-log'),
            onPressed: () => showLogHoursSheet(context, day: _day),
            child: const Text('Log hours'),
          ),
          const SizedBox(height: 8),
          Text(
            'Hours stay on this phone with the business.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _dayView(BuildContext context, DayHours day) {
    final colors = PesaColors.of(context);
    if (day.entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'Hours you log for this day show here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: colors.textMuted),
          ),
        ),
      ];
    }
    final toBill = day.toBill;
    final toBillMinutes = toBill.values.fold(0, (a, b) => a + b);
    return [
      _card([
        for (final e in day.entries)
          _Row(
            e.what,
            '${hoursText(e.minutes)} h',
            key: Key('hour-${e.id}'),
            detail: [
              clientName(e.client),
              ?e.project,
              if (!e.billable) 'not billed',
              if (e.invoiceId != null) 'billed',
            ].join(' · '),
            onTap: () => showLogHoursSheet(context, entry: e),
          ),
      ]),
      const SizedBox(height: 12),
      _card([
        _Row(
          'Day total',
          '${hoursText(day.totalMinutes)} h',
          key: const Key('hours-day-total'),
          detail: day.entries.length == 1
              ? '1 entry'
              : '${day.entries.length} entries',
        ),
        _Row(
          'To bill',
          '${hoursText(toBillMinutes)} h',
          detail: [
            for (final MapEntry(:key, :value) in toBill.entries)
              '${clientShort(key)} ${hoursText(value)} h',
          ].join(' · '),
          color: colors.successText,
        ),
      ]),
    ];
  }

  List<Widget> _weekView(
    BuildContext context,
    WeekHours week,
    String Function(int) plain,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    if (week.entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'Hours you log this week show here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
      ];
    }
    final notWhat = week.notBilledWhat;
    return [
      _card([
        for (final d in week.days)
          _Row(
            '${weekdayName(d.day).substring(0, 3)} ${shortDate(d.day)}',
            '${hoursText(d.totalMinutes)} h',
            detail: [
              for (final MapEntry(:key, :value) in d.toBill.entries)
                '${clientShort(key)} ${hoursText(value)}',
              if (d.notBilledMinutes > 0)
                '${hoursText(d.notBilledMinutes)} not billed',
            ].join(' · '),
            onTap: () => setState(() {
              _day = d.day;
              _week = false;
            }),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(
          'BY PROJECT',
          style: theme.textTheme.labelLarge!.copyWith(
            color: colors.textMuted,
            letterSpacing: 1,
          ),
        ),
      ),
      _card([
        for (final p in week.projects)
          _Row(
            [clientName(p.client), ?p.project].join(' · '),
            p.rateMinor == null && p.amountMinor == 0
                ? '${hoursText(p.minutes)} h'
                : plain(p.amountMinor),
            detail: p.rateMinor == null
                ? '${hoursText(p.minutes)} h'
                : '${hoursText(p.minutes)} h × ${plain(p.rateMinor!)}',
          ),
        if (week.notBilledMinutes > 0)
          _Row(
            'Not billed',
            '${hoursText(week.notBilledMinutes)} h',
            detail: notWhat.take(3).join(', '),
          ),
      ]),
      const SizedBox(height: 12),
      _card([
        _Row(
          'This week',
          plain(week.amountMinor),
          key: const Key('hours-week-total'),
          detail:
              '${hoursText(week.loggedMinutes)} h logged · '
              '${hoursText(week.toBillMinutes)} h to bill',
          color: colors.successText,
        ),
      ]),
    ];
  }
}

Widget _card(List<Widget> rows) => Card(
  margin: EdgeInsets.zero,
  child: Column(
    children: [
      for (final (i, r) in rows.indexed) ...[
        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
        r,
      ],
    ],
  ),
);

class _Row extends StatelessWidget {
  const _Row(
    this.name,
    this.amount, {
    this.detail,
    this.color,
    this.onTap,
    super.key,
  });

  final String name;
  final String amount;
  final String? detail;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  if (detail case final d? when d.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      d,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amount,
              style: theme.textTheme.titleMedium!.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
