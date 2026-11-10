import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/income/week_by_week.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/income_providers.dart';

/// For business and gigs: this week against a usual one, and the rainy day fund
/// that smooths good weeks into lean ones.
class WeekByWeekScreen extends ConsumerWidget {
  const WeekByWeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(weekByWeekProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Week by week'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: switch (plan) {
        AsyncData(:final value) => _Body(value),
        AsyncError() => ErrorView(
          'Week by week could not load.',
          onRetry: () => ref.invalidate(weekByWeekProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.plan);

  final WeekByWeek plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final week = plan.thisWeek;
    final add = plan.suggestAddMinor;
    final take = plan.suggestTakeMinor;
    final fund = plan.fund.balanceMinor;
    final target = plan.targetMinor;
    String day(CalendarDate d) =>
        '${weekdayName(d).substring(0, 3)} ${shortDate(d)}';

    final String? advice;
    if (add > 0) {
      advice =
          'A good week: ${_plain(context, plan.extraMinor)} more than a usual one. '
          'Put ${_plain(context, add)} in your rainy day fund?';
    } else if (take > 0) {
      advice =
          'A lean week so far. You can take up to ${_plain(context, take)} from your '
          'rainy day fund to reach your usual spending.';
    } else {
      advice = null;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Layout.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This week · ${day(week.start)} – ${day(week.end)}',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Figure('In', week.inMinor, color: colors.successText),
                    const SizedBox(width: 24),
                    _Figure(
                      'Out',
                      week.outMinor,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
                if (advice != null) ...[
                  const SizedBox(height: 12),
                  Text(advice, style: theme.textTheme.bodyMedium),
                ],
                if (add > 0) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('rainy-day-add'),
                    onPressed: () =>
                        ref.read(rainyDayFundProvider.notifier).move(add),
                    child: Text(
                      'Add ${_plain(context, add)} to your rainy day fund',
                    ),
                  ),
                ] else if (take > 0) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('rainy-day-take'),
                    onPressed: () =>
                        ref.read(rainyDayFundProvider.notifier).move(-take),
                    child: Text(
                      'Take ${_plain(context, take)} from your rainy day fund',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('rainy-day-fund'),
          child: Padding(
            padding: const EdgeInsets.all(Layout.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rainy day fund',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      target > 0
                          ? '${_plain(context, fund)} of ${_plain(context, target)}'
                          : _plain(context, fund),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (target > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (fund / target).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      color: theme.colorScheme.primary,
                      backgroundColor: colors.border,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'The aim is one usual week of spending. It stays in your '
                  'accounts, set aside here and kept out of safe to spend.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Layout.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Last $weeksShown weeks',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _Key('In', colors.successText),
                    const SizedBox(width: 10),
                    _Key('Out', colors.textMuted),
                  ],
                ),
                const SizedBox(height: 12),
                _WeekBars(plan.shown),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.minor, {required this.color});

  final String label;
  final int minor;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: PesaColors.of(context).textMuted),
      ),
      Text(_plain(context, minor), style: AppTypography.tileFigure(color)),
    ],
  );
}

class _Key extends StatelessWidget {
  const _Key(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _WeekBars extends StatelessWidget {
  const _WeekBars(this.weeks);

  final List<WeekFlow> weeks;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    var most = 1;
    for (final w in weeks) {
      if (w.inMinor > most) most = w.inMinor;
      if (w.outMinor > most) most = w.outMinor;
    }
    Widget bar(int minor, Color color) => Container(
      width: 12,
      height: _height * minor / most,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Semantics(
      label: [
        for (final w in weeks)
          'Week of ${shortDate(w.start)}: in ${_plain(context, w.inMinor)}, '
              'out ${_plain(context, w.outMinor)}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (final (i, w) in weeks.indexed)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: _height,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(
                            w.inMinor,
                            i == weeks.length - 1
                                ? colors.successText
                                : colors.successText.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 3),
                          bar(w.outMinor, colors.border),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      shortDate(w.start),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _plain(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: false);
