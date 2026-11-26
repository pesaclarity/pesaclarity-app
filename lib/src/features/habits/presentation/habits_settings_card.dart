import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/habits/habit_settings.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/pesa_colors.dart';
import '../../reminders/application/reminders_controller.dart';
import '../../settings/application/week_start_provider.dart';
import '../application/habits_providers.dart';
import 'habits_text.dart';

/// Profile › Habits: the no-spend card and the Sunday check-in on Home,
/// each with its own switch, and when the check-in notification comes.
class HabitsSettingsCard extends ConsumerWidget {
  const HabitsSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(habitSettingsProvider).value;
    final remindersOn =
        ref.watch(remindersControllerProvider).value?.enabled ?? false;
    final theme = Theme.of(context);
    void set(HabitSettings Function(HabitSettings) update) =>
        ref.read(habitSettingsProvider.notifier).change(update);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(HabitsText.habits),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                key: const Key('habits-no-spend'),
                title: const Text(HabitsText.noSpendSetting),
                subtitle: const Text(HabitsText.noSpendSettingDetail),
                value: settings?.noSpendOnHome ?? true,
                onChanged: settings == null
                    ? null
                    : (on) => set((s) => s.copyWith(noSpendOnHome: on)),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                key: const Key('habits-check-in'),
                title: const Text(HabitsText.checkInSetting),
                subtitle: const Text(HabitsText.checkInSettingDetail),
                value: settings?.sundayCheckIn ?? true,
                onChanged: settings == null
                    ? null
                    : (on) => set((s) => s.copyWith(sundayCheckIn: on)),
              ),
              if (settings != null && settings.sundayCheckIn) ...[
                const Divider(height: 1),
                ChoiceTile<int?>(
                  title: const Text(HabitsText.notifyMe),
                  subtitle: remindersOn
                      ? null
                      : const Text(HabitsText.notifyNeedsReminders),
                  trailing: ChoiceMenu<int?>(
                    key: const Key('habits-notify'),
                    name: HabitsText.notifyMe,
                    options: [
                      for (final minute in HabitSettings.notifyChoices)
                        (
                          minute,
                          notifyLabel(
                            minute,
                            weekStartsOn: ref.watch(weekStartsOnProvider),
                          ),
                        ),
                    ],
                    value: settings.notifyMinuteOfDay,
                    itemKey: (minute) =>
                        Key('habits-notify-${minute ?? 'off'}'),
                    onChanged: (minute) =>
                        set((s) => s.copyWith(notifyMinuteOfDay: () => minute)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            HabitsText.settingsFooter,
            style: theme.textTheme.bodySmall!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
