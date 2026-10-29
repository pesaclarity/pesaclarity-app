import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/subscriptions_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/reminders/recurring_charges.dart';
import '../../../domain/reminders/reminder_schedule.dart';
import '../../../domain/reminders/reminder_settings.dart';
import '../../../domain/subscriptions/subscriptions.dart';
import '../../../domain/time/calendar.dart';
import '../../home/application/safe_to_spend_provider.dart';
import '../data/reminder_notifications.dart';

/// Whether reminder notifications may show amounts. False keeps amounts off
/// the lock screen.
// TODO(hide-balances): derive from the "Hide balances on open" setting.
final notificationAmountsVisibleProvider = Provider<bool>((ref) => true);

/// The saved reminder settings. Every change reschedules the reminders.
class RemindersController extends AsyncNotifier<ReminderSettings> {
  static const settingsKey = 'reminders.settings';

  @override
  Future<ReminderSettings> build() async {
    final json = await ref
        .read(appSettingsRepositoryProvider)
        .readJson(settingsKey);
    return json == null
        ? const ReminderSettings()
        : ReminderSettings.fromJson(json);
  }

  /// Turns reminders on or off. Turning them on asks for notification
  /// permission first; returns false, leaving them off, when it is refused.
  Future<bool> setEnabled(bool enabled) async {
    final notifications = ref.read(reminderNotificationsProvider);
    if (enabled && !await notifications.requestPermission()) return false;
    await change((s) => s.copyWith(enabled: enabled));
    return true;
  }

  /// Saves [update] applied to the current settings, then reschedules.
  Future<void> change(
    ReminderSettings Function(ReminderSettings) update,
  ) async {
    final current = state.value ?? await future;
    final next = update(current);
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
    await ref.read(reminderSyncProvider).sync();
  }
}

final remindersControllerProvider =
    AsyncNotifierProvider<RemindersController, ReminderSettings>(
      RemindersController.new,
    );

/// Keeps the scheduled notifications in step with the plan and the ledger:
/// on app start, whenever reminder settings change, and shortly after the
/// plan, categories or transactions change.
class ReminderSync {
  ReminderSync(this._ref);

  /// How long to wait after a data change, so a batch of new transactions
  /// reschedules once.
  static const settleDelay = Duration(seconds: 2);

  final Ref _ref;
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _enabled = false;
  bool _disposed = false;

  /// Reschedules after [settleDelay], unless reminders are off.
  void dataChanged() {
    if (!_enabled || _disposed) return;
    _timer?.cancel();
    _timer = Timer(settleDelay, sync);
  }

  /// Works out the reminders from today's data and replaces the scheduled
  /// ones. Calls made while one is running fold into a single rerun.
  Future<void> sync() async {
    _timer?.cancel();
    if (_disposed) return;
    if (_running != null) {
      _again = true;
      return _running;
    }
    _running = _syncLoop();
    try {
      await _running;
    } finally {
      _running = null;
    }
  }

  Future<void> _syncLoop() async {
    do {
      _again = false;
      try {
        await _syncOnce();
      } catch (error, stack) {
        debugPrint('Reminder scheduling failed: $error\n$stack');
      }
    } while (_again && !_disposed);
  }

  Future<void> _syncOnce() async {
    final settings = await _ref.read(remindersControllerProvider.future);
    final notifications = _ref.read(reminderNotificationsProvider);
    final wasEnabled = _enabled;
    _enabled = settings.enabled;
    if (!settings.enabled) {
      if (wasEnabled) await notifications.cancelAll();
      return;
    }
    final reminders = await _plan(settings);
    if (_disposed) return;
    await notifications.replaceAll(reminders);
  }

  Future<List<Reminder>> _plan(ReminderSettings settings) async {
    final now = _ref.read(clockProvider)();
    final today = CalendarDate.local(now);
    final month = today.yearMonth;
    final plans = _ref.read(planRepositoryProvider);
    final entries = await _ref
        .read(transactionsRepositoryProvider)
        .ledgerEntries(
          from: month.addMonths(-2).startInstant,
          to: today.addDays(1).startInstant,
        );

    final reviews = [
      MonthReview.of(await plans.monthPlan(month), entries),
      MonthReview.of(await plans.monthPlan(month.next), const []),
    ];
    final bills = <DuePayment>[];
    final paydays = <DuePayment>[];
    for (final review in reviews) {
      final due = duePaymentsIn(review);
      bills.addAll(due.bills);
      paydays.addAll(due.paydays);
    }

    // Tracked subscriptions are reminded at their own next date; suggested
    // charges only until they are tracked or marked as one-offs.
    final subscriptions = SubscriptionsOverview.of(
      saved: await _ref.read(subscriptionsRepositoryProvider).watchAll().first,
      entries: entries,
      today: today,
    );
    final billNames = {for (final b in bills) b.name.trim().toLowerCase()};
    final charges = [
      for (final line in subscriptions.lines)
        if (!billNames.contains(line.subscription.name.trim().toLowerCase()))
          RecurringCharge(
            name: line.subscription.name,
            payeeId: line.subscription.payeeId,
            amountMinor: line.amountMinor,
            currency: line.subscription.currency,
            lastDate: line.lastChargedOn ?? line.nextDate,
            nextDate: line.nextDate,
          ),
      for (final charge in subscriptions.suggestions)
        if (!billNames.contains(charge.name.trim().toLowerCase())) charge,
    ];

    int? safeToday;
    if (settings.dailySafeToSpend) {
      _ref.invalidate(safeToSpendTodayProvider);
      safeToday = (await _ref.read(safeToSpendTodayProvider.future))
          ?.leftTodayMinor;
    }

    return planReminders(
      settings: settings,
      now: now,
      bills: bills,
      paydays: paydays,
      charges: charges,
      safeToSpendTodayMinor: safeToday,
      showAmounts: _ref.read(notificationAmountsVisibleProvider),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// The running [ReminderSync]. Reading it starts a first sync and watches
/// the database for changes; the app shell keeps it alive.
final reminderSyncProvider = Provider<ReminderSync>((ref) {
  final sync = ReminderSync(ref);
  final db = ref.watch(appDatabaseProvider);
  final changes = db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          db.recurring,
          db.budgetItems,
          db.categories,
          db.transactions,
          db.payees,
          db.subscriptions,
        ]),
      )
      .listen((_) => sync.dataChanged());
  ref.listen(notificationAmountsVisibleProvider, (_, _) => sync.sync());
  ref.onDispose(() {
    changes.cancel();
    sync.dispose();
  });
  Future.microtask(sync.sync);
  return sync;
});
