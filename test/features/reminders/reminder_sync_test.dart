import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_schedule.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_settings.dart';
import 'package:pesaclarity/src/features/reminders/application/reminders_controller.dart';
import 'package:pesaclarity/src/features/reminders/data/reminder_notifications.dart';

import '../../domain/fixtures.dart';
import '../../helpers/fake_reminders.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late FakeReminderNotifications notifications;

  // Monday 26 October 2026, 07:00 in Nairobi.
  final now = eat(2026, 10, 26, 7);

  ProviderContainer container({bool showAmounts = true}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        reminderNotificationsProvider.overrideWithValue(notifications),
        notificationAmountsVisibleProvider.overrideWithValue(showAmounts),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> addRecurring(
    String name,
    CategoryType type,
    int day,
    int shillings,
  ) async {
    final category = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'Test $name', type: type));
    await db
        .into(db.recurring)
        .insert(
          RecurringCompanion.insert(
            name: name,
            categoryId: Value(category),
            amountMinor: kes(shillings),
            frequency: RecurrenceFrequency.monthly,
            startDate: eat(2026, 1, day, 0),
          ),
        );
  }

  setUp(() async {
    db = openTestDatabase();
    notifications = FakeReminderNotifications();
    await addRecurring('Rent', CategoryType.expense, 1, 25000);
    await addRecurring('Salary', CategoryType.income, 30, 80000);
  });

  test('turning reminders on asks permission and schedules the plan', () async {
    final c = container();
    final done = await c
        .read(remindersControllerProvider.notifier)
        .setEnabled(true);

    expect(done, isTrue);
    expect(notifications.permissionRequests, 1);
    expect(notifications.scheduled.map((r) => (r.kind, r.at, r.title)), [
      (ReminderKind.payday, eat(2026, 10, 30, 9), 'Payday: Salary'),
      (ReminderKind.bill, eat(2026, 10, 31, 9), 'Rent is due tomorrow'),
      (ReminderKind.payday, eat(2026, 11, 30, 9), 'Payday: Salary'),
    ]);
    expect(notifications.scheduled[1].body, contains('KES 25,000'));
  });

  test('a refused permission leaves reminders off', () async {
    notifications.grant = false;
    final c = container();
    final done = await c
        .read(remindersControllerProvider.notifier)
        .setEnabled(true);

    expect(done, isFalse);
    expect((await c.read(remindersControllerProvider.future)).enabled, isFalse);
    expect(notifications.schedules, isEmpty);
  });

  test('turning reminders off cancels them', () async {
    final c = container();
    final controller = c.read(remindersControllerProvider.notifier);
    await controller.setEnabled(true);
    await controller.setEnabled(false);

    expect(notifications.cancels, 1);
    expect(notifications.scheduled, isEmpty);
  });

  test('hides amounts when amounts are not to be shown', () async {
    final c = container(showAmounts: false);
    await c.read(remindersControllerProvider.notifier).setEnabled(true);

    expect(notifications.scheduled, isNotEmpty);
    for (final r in notifications.scheduled) {
      expect(r.body, isNot(contains('KES')));
    }
  });

  test('reschedules on start and after the plan changes', () async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: RemindersController.settingsKey,
            value: '{"enabled": true, "leadDays": 0}',
          ),
        );
    final c = container();
    c.listen(reminderSyncProvider, (_, _) {});
    await pumpEventQueue();
    expect(notifications.scheduled.map((r) => r.title), [
      'Payday: Salary',
      'Rent is due today',
      'Payday: Salary',
    ]);

    await addRecurring('Internet', CategoryType.expense, 28, 3000);
    await Future<void>.delayed(
      ReminderSync.settleDelay + const Duration(milliseconds: 300),
    );
    expect(
      notifications.scheduled.map((r) => r.title),
      contains('Internet is due today'),
    );
  });

  test('starting with reminders off touches no notifications', () async {
    final c = container();
    c.listen(reminderSyncProvider, (_, _) {});
    await pumpEventQueue();
    await addRecurring('Internet', CategoryType.expense, 28, 3000);
    await pumpEventQueue();

    expect(notifications.schedules, isEmpty);
    expect(notifications.cancels, 0);
    expect(c.read(remindersControllerProvider).value, const ReminderSettings());
  });
}
