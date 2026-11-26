import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/time/week_start.dart';
import '../../reminders/application/reminders_controller.dart';

/// Profile › Week starts on: the day the week starts on, for the whole app
/// (kept with Personal, whichever space is open). Monday by default.
class WeekStartController extends AsyncNotifier<int> {
  static const settingsKey = 'week.startsOn';

  @override
  Future<int> build() async {
    final saved = await ref
        .watch(mainSettingsRepositoryProvider)
        .readJson(settingsKey);
    final day = switch (saved?['weekday']) {
      final int d when d >= DateTime.monday && d <= DateTime.sunday => d,
      _ => DateTime.monday,
    };
    FirstWeekday.set(day);
    return day;
  }

  /// Saves [weekday] and moves the weekly check-in's notification to the
  /// new last day of the week.
  Future<void> change(int weekday) async {
    await ref.read(mainSettingsRepositoryProvider).writeJson(settingsKey, {
      'weekday': weekday,
    });
    FirstWeekday.set(weekday);
    state = AsyncData(weekday);
    try {
      await ref.read(reminderSyncProvider).sync();
    } on Object catch (error) {
      debugPrint('Reminders not moved to the new week: $error');
    }
  }
}

final weekStartControllerProvider =
    AsyncNotifierProvider<WeekStartController, int>(WeekStartController.new);

/// The weekday the week starts on; Monday until the setting has loaded.
final weekStartsOnProvider = Provider<int>(
  (ref) => ref.watch(weekStartControllerProvider).value ?? DateTime.monday,
);
