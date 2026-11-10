import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/books/business_report.dart'
    show ReportPeriod, periodText;
import '../../../domain/hours/hours.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
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
    final loaded = ref.watch(weekHoursProvider(from));
    final week = loaded.value;
    final hidden = AmountsHidden.of(context);
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);
    final title = _week
        ? periodText(
            ReportPeriod(from, from.addDays(7), ''),
            thisYear: today.year,
          )
        : _day == today
        ? 'Today, ${shortDate(_day)}'
        : '${weekdayName(_day)} ${shortDate(_day)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hours'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          AdaptiveSegmented<bool>(
            key: const Key('hours-day-week'),
            segments: const [(false, 'Day'), (true, 'Week')],
            selected: _week,
            showSelectedIcon: false,
            onChanged: (week) => setState(() => _week = week),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              StepButton(
                key: const Key('hours-back'),
                tooltip: _week ? 'Previous week' : 'Previous day',
                icon: Icons.chevron_left,
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
              StepButton(
                key: const Key('hours-next'),
                tooltip: _week ? 'Next week' : 'Next day',
                icon: Icons.chevron_right,
                onPressed: () =>
                    setState(() => _day = _day.addDays(_week ? 7 : 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (week == null && loaded.hasError)
            ErrorView(
              'Your hours could not load.',
              onRetry: () => ref.invalidate(weekHoursProvider(from)),
            )
          else if (week == null)
            const LoadingView(inList: true)
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
    if (day.entries.isEmpty) {
      return const [EmptyNote('Hours you log for this day show here.')];
    }
    final toBill = day.toBill;
    final toBillMinutes = toBill.values.fold(0, (a, b) => a + b);
    return [
      GroupedSection(
        children: [
          for (final e in day.entries)
            LabelValueRow(
              key: Key('hour-${e.id}'),
              label: e.what,
              value: '${hoursText(e.minutes)} h',
              detail: _detail([
                clientName(e.client),
                ?e.project,
                if (!e.billable) 'not billed',
                if (e.invoiceId != null) 'billed',
              ]),
              onTap: () => showLogHoursSheet(context, entry: e),
            ),
        ],
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            key: const Key('hours-day-total'),
            label: 'Day total',
            value: '${hoursText(day.totalMinutes)} h',
            detail: day.entries.length == 1
                ? '1 entry'
                : '${day.entries.length} entries',
          ),
          LabelValueRow(
            label: 'To bill',
            value: '${hoursText(toBillMinutes)} h',
            detail: _detail([
              for (final MapEntry(:key, :value) in toBill.entries)
                '${clientShort(key)} ${hoursText(value)} h',
            ]),
          ),
        ],
      ),
    ];
  }

  List<Widget> _weekView(
    BuildContext context,
    WeekHours week,
    String Function(int) plain,
  ) {
    if (week.entries.isEmpty) {
      return const [EmptyNote('Hours you log this week show here.')];
    }
    final notWhat = week.notBilledWhat;
    return [
      GroupedSection(
        children: [
          for (final d in week.days)
            LabelValueRow(
              label:
                  '${weekdayName(d.day).substring(0, 3)} ${shortDate(d.day)}',
              value: '${hoursText(d.totalMinutes)} h',
              detail: _detail([
                for (final MapEntry(:key, :value) in d.toBill.entries)
                  '${clientShort(key)} ${hoursText(value)}',
                if (d.notBilledMinutes > 0)
                  '${hoursText(d.notBilledMinutes)} not billed',
              ]),
              onTap: () => setState(() {
                _day = d.day;
                _week = false;
              }),
            ),
        ],
      ),
      const SectionLabel('By project'),
      GroupedSection(
        children: [
          for (final p in week.projects)
            LabelValueRow(
              label: [clientName(p.client), ?p.project].join(' · '),
              value: p.rateMinor == null && p.amountMinor == 0
                  ? '${hoursText(p.minutes)} h'
                  : plain(p.amountMinor),
              detail: p.rateMinor == null
                  ? '${hoursText(p.minutes)} h'
                  : '${hoursText(p.minutes)} h × ${plain(p.rateMinor!)}',
            ),
          if (week.notBilledMinutes > 0)
            LabelValueRow(
              label: 'Not billed',
              value: '${hoursText(week.notBilledMinutes)} h',
              detail: _detail(notWhat.take(3), separator: ', '),
            ),
        ],
      ),
      const SizedBox(height: 12),
      GroupedSection(
        children: [
          LabelValueRow(
            key: const Key('hours-week-total'),
            label: 'This week',
            value: plain(week.amountMinor),
            detail:
                '${hoursText(week.loggedMinutes)} h logged · '
                '${hoursText(week.toBillMinutes)} h to bill',
          ),
        ],
      ),
    ];
  }
}

/// [parts] joined for a row's detail line, or null when there are none.
String? _detail(Iterable<String> parts, {String separator = ' · '}) =>
    parts.isEmpty ? null : parts.join(separator);
