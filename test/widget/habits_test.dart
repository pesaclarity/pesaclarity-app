import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/habits/habit_settings.dart';
import 'package:pesaclarity/src/domain/habits/no_spend_days.dart';
import 'package:pesaclarity/src/domain/habits/week_check_in.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_schedule.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/habits/application/habits_providers.dart';
import 'package:pesaclarity/src/features/habits/presentation/habits_home_cards.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_reminders.dart';
import '../helpers/test_app.dart';

/// Sunday 22 November 2026.
final _sunday = CalendarDate(2026, 11, 22);

/// Mon 1,240; Tue none; Wed 380; Thu 2,100; Fri a KPLC bill; Sat none.
NoSpendDays _week(CalendarDate today) => NoSpendDays.of(
  [
    entry(at: eat(2026, 11, 16), amount: kes(1240)),
    entry(at: eat(2026, 11, 18), amount: kes(380)),
    entry(at: eat(2026, 11, 19), amount: kes(2100)),
    entry(at: eat(2026, 11, 20), amount: kes(1800), categoryId: 9),
  ],
  today: today,
  historyFrom: CalendarDate(2026, 11, 1),
  scheduledCategoryIds: {9},
);

final _week3 = WeekCheckIn(
  start: CalendarDate(2026, 11, 16),
  end: _sunday,
  spentMinor: 370000,
  lastWeekMinor: 780000,
  noSpendDays: 3,
  noSpendBestThisMonth: true,
  mostChanged: (categoryId: 1, changeMinor: -300000),
  aboveUsual: (categoryId: 2, changeMinor: 190000),
  usualMinor: 150000,
);

Future<void> _pumpCards(
  WidgetTester tester, {
  required AppDatabase db,
  required NoSpendDays days,
  WeekCheckIn? week,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        noSpendDaysProvider.overrideWith((ref) async => days),
        weekCheckInProvider.overrideWith((ref) async => week),
        categoryNamesProvider.overrideWith(
          (ref) => Stream.value(const {1: 'Eating out', 2: 'Transport'}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [SundayCheckInCard(), NoSpendCard()]),
          ),
        ),
      ),
    ),
  );
  await settleFrames(tester);
}

void main() {
  testAppWidgets('the no-spend card opens the week', (tester) async {
    final db = openTestDatabase();
    await _pumpCards(tester, db: db, days: _week(_sunday));
    expect(find.text('3 no-spend days this week'), findsOneWidget);
    expect(
      find.text('Streak: 2 days · bills, moves and savings do not count'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('home-no-spend')));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsNWidgets(3));
    expect(find.text('1,240'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Streak now'), findsOneWidget);
    expect(find.text('No-spend days in Nov'), findsOneWidget);
    expect(
      find.text('Friday had a bill. It does not break a no-spend day.'),
      findsOneWidget,
    );
  });

  testAppWidgets('no card until the week has a no-spend day', (tester) async {
    final db = openTestDatabase();
    // Monday: nothing is counted yet.
    await _pumpCards(tester, db: db, days: _week(CalendarDate(2026, 11, 16)));
    expect(find.byKey(const Key('home-no-spend')), findsNothing);
  });

  testAppWidgets('the weekly check-in shows three lines', (tester) async {
    final db = openTestDatabase();
    await _pumpCards(tester, db: db, days: _week(_sunday), week: _week3);
    expect(find.text('Your week in three lines'), findsOneWidget);
    expect(find.text('Weekly check-in · ready'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-check-in')));
    await tester.pumpAndSettle();
    expect(find.text('Mon 16 to Sun 22 Nov'), findsOneWidget);
    expect(
      find.text(
        'You spent 4,100 less than last week, most of it on eating out.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Three no-spend days, the most this month.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Transport is 1,900 above its usual week. Try keeping it to 1,500.',
      ),
      findsOneWidget,
    );
    expect(find.text('See Insights'), findsOneWidget);
  });

  testAppWidgets('turned off in Profile, the cards hide', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => DriftAppSettingsRepository(db).writeJson(
        HabitSettingsController.settingsKey,
        const HabitSettings(
          noSpendOnHome: false,
          sundayCheckIn: false,
        ).toJson(),
      ),
    );
    await _pumpCards(tester, db: db, days: _week(_sunday), week: _week3);
    expect(find.byKey(const Key('home-no-spend')), findsNothing);
    expect(find.byKey(const Key('home-check-in')), findsNothing);
  });

  testAppWidgets('Profile › Habits turns each off and sets the notification', (
    tester,
  ) async {
    final db = openTestDatabase();
    final notifications = FakeReminderNotifications();
    await pumpApp(tester, db: db, notifications: notifications);
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    await tapText(tester, 'Reminders');
    await settleFrames(tester);
    expect(
      notifications.scheduled.where(
        (r) => r.kind == ReminderKind.weeklyCheckIn,
      ),
      hasLength(1),
    );

    await scrollTo(tester, find.text('HABITS'));
    expect(find.text('No-spend days on Home'), findsOneWidget);
    expect(find.text('Sunday at 18:00'), findsOneWidget);
    await tapText(tester, 'Weekly check-in');
    await settleFrames(tester);
    expect(find.text('Notify me'), findsNothing);
    expect(
      notifications.scheduled.where(
        (r) => r.kind == ReminderKind.weeklyCheckIn,
      ),
      isEmpty,
    );
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(HabitSettingsController.settingsKey),
    );
    expect(saved, containsPair('sundayCheckIn', false));
    expect(saved, containsPair('noSpendOnHome', true));
  });
}
