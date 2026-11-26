import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/habits/week_check_in.dart';
import '../../../theme/pesa_colors.dart';
import '../../settings/application/week_start_provider.dart';
import '../application/habits_providers.dart';
import 'habits_sheets.dart';
import 'habits_text.dart';

/// On Sunday, "Your week in three lines": opens the check-in. Hidden when
/// turned off in Profile › Habits.
class SundayCheckInCard extends ConsumerWidget {
  const SundayCheckInCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(habitSettingsProvider).value;
    final week = ref.watch(weekCheckInProvider).value;
    if (settings == null || !settings.sundayCheckIn || week == null) {
      return const SizedBox.shrink();
    }
    if (!isCheckInDay(week.end, ref.watch(weekStartsOnProvider))) {
      return const SizedBox.shrink();
    }
    return _HabitCard(
      key: const Key('home-check-in'),
      title: HabitsText.checkInTitle,
      subtitle: HabitsText.checkInReady,
      onTap: () => showWeekCheckInSheet(context, week),
    );
  }
}

/// "3 no-spend days this week" with the streak, once the week has a
/// no-spend day. Hidden when turned off in Profile › Habits.
class NoSpendCard extends ConsumerWidget {
  const NoSpendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(habitSettingsProvider).value;
    final days = ref.watch(noSpendDaysProvider).value;
    if (settings == null || !settings.noSpendOnHome || days == null) {
      return const SizedBox.shrink();
    }
    if (days.weekCount == 0) return const SizedBox.shrink();
    return _HabitCard(
      key: const Key('home-no-spend'),
      title: HabitsText.weekCount(days.weekCount),
      subtitle: HabitsText.streakLine(days.streak),
      onTap: () => showNoSpendWeekSheet(context, days),
    );
  }
}

/// A plain card with a title, a line under it and a chevron.
class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right,
          color: PesaColors.of(context).textMuted,
        ),
        onTap: onTap,
      ),
    ),
  );
}
