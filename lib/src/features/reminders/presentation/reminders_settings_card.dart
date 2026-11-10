import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/reminders/reminder_settings.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../application/reminders_controller.dart';

/// The Reminders section of Profile: what to be reminded about, how early,
/// and when the daily safe-to-spend notification shows.
class RemindersSettingsCard extends ConsumerWidget {
  const RemindersSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(remindersControllerProvider).value;
    final controller = ref.read(remindersControllerProvider.notifier);

    void set(ReminderSettings Function(ReminderSettings) update) =>
        controller.change(update);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(
          'Reminders',
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text('Reminders'),
                subtitle: const Text(
                  'Notifications from this phone before money is due',
                ),
                value: settings?.enabled ?? false,
                onChanged: settings == null
                    ? null
                    : (on) => _setEnabled(context, ref, on),
              ),
              if (settings != null && settings.enabled) ...[
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: const Text('Bills'),
                  subtitle: const Text('Unpaid bills in your plan'),
                  value: settings.bills,
                  onChanged: (on) => set((s) => s.copyWith(bills: on)),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: const Text('Card charges'),
                  subtitle: const Text('Charges that repeat every month'),
                  value: settings.cardCharges,
                  onChanged: (on) => set((s) => s.copyWith(cardCharges: on)),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: const Text('Payday'),
                  subtitle: const Text('A nudge to split your pay'),
                  value: settings.payday,
                  onChanged: (on) => set((s) => s.copyWith(payday: on)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Remind me'),
                  trailing: ChoiceMenu<int>(
                    key: const Key('reminders-lead-days'),
                    name: 'Remind me',
                    options: [
                      for (final option in ReminderSettings.leadDayChoices)
                        (option, leadDaysLabel(option)),
                    ],
                    value: settings.leadDays,
                    itemKey: (days) => Key('lead-days-$days'),
                    onChanged: (days) => set((s) => s.copyWith(leadDays: days)),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  title: const Text('Daily safe-to-spend'),
                  subtitle: const Text('What you can spend today'),
                  value: settings.dailySafeToSpend,
                  onChanged: (on) =>
                      set((s) => s.copyWith(dailySafeToSpend: on)),
                ),
                if (settings.dailySafeToSpend) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Daily at'),
                    trailing: Text(
                      _timeOf(settings.dailyMinuteOfDay).format(context),
                    ),
                    onTap: () =>
                        _pickTime(context, ref, settings.dailyMinuteOfDay),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setEnabled(BuildContext context, WidgetRef ref, bool on) async {
    final done = await ref
        .read(remindersControllerProvider.notifier)
        .setEnabled(on);
    if (!done && context.mounted) {
      showNote(
        context,
        'Allow notifications for Pesa Clarity in phone settings to get '
        'reminders.',
      );
    }
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final picked = await pickTime(
      context,
      initialTime: _timeOf(current),
      helpText: 'Daily safe-to-spend at',
    );
    if (picked != null) {
      await ref
          .read(remindersControllerProvider.notifier)
          .change(
            (s) =>
                s.copyWith(dailyMinuteOfDay: picked.hour * 60 + picked.minute),
          );
    }
  }

  static TimeOfDay _timeOf(int minuteOfDay) =>
      TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60);
}
