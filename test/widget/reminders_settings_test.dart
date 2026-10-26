import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/reminders/application/reminders_controller.dart';

import '../helpers/fake_reminders.dart';
import '../helpers/test_app.dart';

void main() {
  Future<void> openProfile(WidgetTester tester) async {
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
  }

  testAppWidgets('turning reminders on shows their settings', (tester) async {
    final db = openTestDatabase();
    final notifications = FakeReminderNotifications();
    await pumpApp(tester, db: db, notifications: notifications);
    await openProfile(tester);

    await scrollTo(tester, find.text('REMINDERS'));
    expect(find.text('REMINDERS'), findsOneWidget);
    expect(find.text('Bills'), findsNothing);

    await tapText(tester, 'Reminders');
    expect(notifications.permissionRequests, 1);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Card charges'), findsOneWidget);
    expect(find.text('Payday'), findsOneWidget);
    expect(find.text('1 day before'), findsOneWidget);

    await tapText(tester, 'Remind me');
    await tester.tap(find.text('3 days before'));
    await tester.pumpAndSettle();
    expect(find.text('3 days before'), findsOneWidget);

    await tapText(tester, 'Daily safe-to-spend');
    expect(find.text('Daily at'), findsOneWidget);

    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(RemindersController.settingsKey),
    );
    expect(saved, containsPair('enabled', true));
    expect(saved, containsPair('leadDays', 3));
    expect(saved, containsPair('dailySafeToSpend', true));
  });

  testAppWidgets('a refused permission keeps reminders off', (tester) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      notifications: FakeReminderNotifications(grant: false),
    );
    await openProfile(tester);

    await tapText(tester, 'Reminders');
    expect(find.text('Bills'), findsNothing);
    expect(
      find.text(
        'Allow notifications for Pesa Clarity in phone settings to get '
        'reminders.',
      ),
      findsOneWidget,
    );
    final tile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Reminders'),
    );
    expect(tile.value, isFalse);
  });
}
