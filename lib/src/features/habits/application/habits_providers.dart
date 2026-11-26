import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../domain/habits/habit_settings.dart';
import '../../../domain/habits/no_spend_days.dart';
import '../../../domain/habits/week_check_in.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/time/calendar.dart';
import '../../reminders/application/reminders_controller.dart';
import '../../settings/application/week_start_provider.dart';

/// Profile › Habits. A change reschedules the reminders, which carry the
/// Sunday check-in notification.
class HabitSettingsController extends AsyncNotifier<HabitSettings> {
  static const settingsKey = 'habits.settings';

  @override
  Future<HabitSettings> build() async => HabitSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> change(HabitSettings Function(HabitSettings) update) async {
    final next = update(state.value ?? await future);
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
    await ref.read(reminderSyncProvider).sync();
  }
}

final habitSettingsProvider =
    AsyncNotifierProvider<HabitSettingsController, HabitSettings>(
      HabitSettingsController.new,
    );

/// What the habits read: the records back far enough for a streak and
/// four usual weeks, Plan's bills and the cash accounts.
class _HabitRecords {
  const _HabitRecords({
    required this.today,
    required this.entries,
    required this.historyFrom,
    required this.scheduledIds,
    required this.cashIds,
  });

  final CalendarDate today;
  final List<LedgerEntry> entries;
  final CalendarDate historyFrom;
  final Set<int> scheduledIds;
  final Set<int> cashIds;
}

final _habitRecordsProvider = FutureProvider<_HabitRecords?>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final accounts = [
    for (final a in await ref.watch(accountsRepositoryProvider).openings())
      if (!a.isSavings) a,
  ];
  if (accounts.isEmpty) return null;
  var opened = accounts.first.openingDate;
  for (final a in accounts) {
    if (a.openingDate.isBefore(opened)) opened = a.openingDate;
  }
  final from = today.addDays(-noSpendLookBackDays);
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: from.startInstant,
        to: today.addDays(1).startInstant,
        dayToDayOnly: true,
      );
  final plan = await ref
      .watch(planRepositoryProvider)
      .monthPlan(today.yearMonth);
  return _HabitRecords(
    today: today,
    entries: entries,
    historyFrom: CalendarDate.local(opened),
    scheduledIds: scheduledCategoryIds(plan),
    cashIds: {
      for (final a in accounts)
        if (a.type == AccountType.cash) a.id,
    },
  );
});

/// No-spend days this week, the streak and the month's count; null
/// without day-to-day accounts.
final noSpendDaysProvider = FutureProvider<NoSpendDays?>((ref) async {
  final records = await ref.watch(_habitRecordsProvider.future);
  if (records == null) return null;
  return NoSpendDays.of(
    records.entries,
    today: records.today,
    historyFrom: records.historyFrom,
    scheduledCategoryIds: records.scheduledIds,
    cashAccountIds: records.cashIds,
    weekStartsOn: ref.watch(weekStartsOnProvider),
  );
});

/// The week in three lines, worked out on the phone; null without
/// day-to-day accounts.
final weekCheckInProvider = FutureProvider<WeekCheckIn?>((ref) async {
  final records = await ref.watch(_habitRecordsProvider.future);
  final noSpend = await ref.watch(noSpendDaysProvider.future);
  if (records == null || noSpend == null) return null;
  return WeekCheckIn.of(
    records.entries,
    today: records.today,
    noSpend: noSpend,
    scheduledCategoryIds: records.scheduledIds,
  );
});
