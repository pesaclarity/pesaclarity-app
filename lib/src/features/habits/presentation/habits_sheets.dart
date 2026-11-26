import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/habits/no_spend_days.dart';
import '../../../domain/habits/week_check_in.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../insights/application/insights_providers.dart';
import 'habits_text.dart';

/// Opens the week's no-spend days.
Future<void> showNoSpendWeekSheet(BuildContext context, NoSpendDays days) =>
    showAppSheet<void>(
      context: context,
      builder: (context) =>
          AmountsHiddenScope(child: NoSpendWeekSheet(days: days)),
    );

/// Each day this week, "None" where nothing was spent or the amount, then
/// the streak, the longest run this month and the month's count.
class NoSpendWeekSheet extends StatelessWidget {
  const NoSpendWeekSheet({required this.days, super.key});

  final NoSpendDays days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final note = days.latestWithLeftOut;
    return SheetBody(
      title: HabitsText.weekCount(days.weekCount),
      subtitle: HabitsText.noSpendExplained,
      children: [
        Card(child: _Week(days)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                LabelValueRow(
                  key: const Key('no-spend-streak'),
                  label: HabitsText.streakNow,
                  value: HabitsText.days(days.streak),
                ),
                const Divider(height: 1),
                LabelValueRow(
                  label: HabitsText.longestThisMonth,
                  value: HabitsText.days(days.longestThisMonth),
                ),
                const Divider(height: 1),
                LabelValueRow(
                  label: HabitsText.monthCount(days.today.yearMonth),
                  value: '${days.monthCount}',
                ),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            HabitsText.leftOutNote(note),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Monday to Sunday: seven columns, or one row a day at larger text,
/// where seven columns leave too little room for an amount.
class _Week extends StatelessWidget {
  const _Week(this.days);

  final NoSpendDays days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final week = days.week;
    String value(DaySpend day) {
      if (day.date == days.today) return HabitsText.today;
      if (day.date.isAfter(days.today) || !day.counted) return '–';
      if (day.isNoSpend) return HabitsText.none;
      return shownMoney(context, day.spentMinor);
    }

    Color? tone(DaySpend day) => day.isNoSpend ? colors.successText : null;
    String name(DaySpend day) => const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][day.date.weekday - 1];

    if (MediaQuery.textScalerOf(context).scale(1) > 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            for (final day in week)
              LabelValueRow(
                label: name(day),
                value: value(day),
                valueColor: tone(day),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: Layout.cardPadding - 4,
      ),
      child: Row(
        children: [
          for (final day in week)
            Expanded(
              child: Semantics(
                label: '${name(day)}: ${value(day)}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    Text(
                      name(day),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value(day),
                      key: Key('no-spend-day-${day.date.weekday}'),
                      maxLines: 1,
                      style: theme.textTheme.labelMedium!.copyWith(
                        color: tone(day),
                        fontWeight: day.isNoSpend ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the Sunday check-in.
Future<void> showWeekCheckInSheet(BuildContext context, WeekCheckIn week) =>
    showAppSheet<void>(
      context: context,
      builder: (context) =>
          AmountsHiddenScope(child: WeekCheckInSheet(week: week)),
    );

/// The week in three plain lines: what changed, one thing that went well
/// and one suggestion for next week, worked out on the phone.
class WeekCheckInSheet extends ConsumerWidget {
  const WeekCheckInSheet({required this.week, super.key});

  final WeekCheckIn week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final names = ref.watch(categoryNamesProvider).value ?? const {};
    String money(int minor) => shownMoney(context, minor);
    Widget line(String heading, String body, String key) => Padding(
      key: Key(key),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return SheetBody(
      title: HabitsText.weekTitle,
      subtitle: HabitsText.weekRange(week.start, week.end),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(
                HabitsText.whatChanged,
                HabitsText.changed(week, money, names),
                'check-in-changed',
              ),
              const Divider(height: 1),
              line(
                HabitsText.wentWell,
                HabitsText.wentWellLine(week, money, names),
                'check-in-went-well',
              ),
              const Divider(height: 1),
              line(
                HabitsText.nextWeek,
                HabitsText.nextWeekLine(week, money, names),
                'check-in-next-week',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          HabitsText.workedOut,
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('check-in-insights'),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.go(AppRoutes.insights);
                },
                child: const Text(HabitsText.seeInsights),
              ),
            ),
            const SizedBox(width: Layout.cardGap),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
