import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/hours_repository.dart';
import 'package:pesaclarity/src/domain/hours/hours.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/hours/presentation/hours_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

HourEntry _e(
  int id,
  String client,
  String? project,
  String what,
  CalendarDate day,
  int minutes, {
  bool billable = true,
  int? rate,
}) => HourEntry(
  id: id,
  client: client,
  project: project,
  what: what,
  day: day,
  minutes: minutes,
  billable: billable,
  rateMinor: rate,
);

void main() {
  final thu = CalendarDate(2026, 11, 5);

  group('hours', () {
    test('read and written as people say them', () {
      expect(hoursText(90), '1.5');
      expect(hoursText(45), '0.75');
      expect(hoursText(480), '8');
      expect(minutesFrom('1.5'), 90);
      expect(minutesFrom('1,5'), 90);
      expect(minutesFrom('1:30'), 90);
      expect(minutesFrom('20m'), 15);
      expect(minutesFrom('0'), isNull);
      expect(minutesFrom('a while'), isNull);
      expect(clientName('Bidii Traders Ltd'), 'Bidii Traders');
      expect(clientShort('Bidii Traders Ltd'), 'Bidii');
      expect(weekStart(thu), CalendarDate(2026, 11, 2));
    });

    test('a day: total and what is to bill by client', () {
      final day = DayHours(thu, [
        _e(1, 'Bidii Traders Ltd', 'Website revamp', 'Design review', thu, 90),
        _e(
          2,
          'Bidii Traders Ltd',
          'Website revamp',
          'Checkout pages',
          thu,
          210,
        ),
        _e(3, 'Juhudi Sacco', 'Strategy', 'Board meeting', thu, 120),
        _e(4, 'Juhudi Sacco', 'Strategy', 'Travel', thu, 60, billable: false),
      ]);
      expect(day.totalMinutes, 480);
      expect(day.toBill, {'Bidii Traders Ltd': 300, 'Juhudi Sacco': 120});
      expect(day.notBilledMinutes, 60);
    });

    test('a week: by day and by project, at their rates', () {
      final mon = CalendarDate(2026, 11, 2);
      final week = WeekHours(mon, [
        _e(
          1,
          'Bidii Traders Ltd',
          'Website revamp',
          'Build',
          mon,
          27 * 60,
          rate: 250000,
        ),
        _e(
          2,
          'Juhudi Sacco',
          'Strategy',
          'Board meeting',
          thu,
          4 * 60,
          rate: 400000,
        ),
        _e(3, 'Juhudi Sacco', 'Strategy', 'Travel', thu, 60, billable: false),
        _e(4, 'Bidii Traders Ltd', null, 'Next week', mon.addDays(7), 60),
      ]);
      expect(week.loggedMinutes, 32 * 60);
      expect(week.toBillMinutes, 31 * 60);
      expect(week.amountMinor, 8350000);
      expect(week.days.map((d) => d.day), [mon, thu]);
      final projects = week.projects;
      expect(projects.first.amountMinor, 6750000);
      expect(projects.first.rateMinor, 250000);
      expect(week.notBilledWhat, ['Travel']);
    });
  });

  group('screens', () {
    late AppDatabase db;
    final now = eat(2026, 11, 5, 17);

    setUp(() => db = openTestDatabase());

    List<Override> overrides() => [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => now),
      activeSpaceProvider.overrideWithValue(
        const Space(
          id: 'a',
          name: 'Amina Consulting',
          kind: SpaceKind.business,
        ),
      ),
    ];

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      bool week = false,
    }) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: HoursScreen(week: week),
          ),
        ),
      );
      await settleFrames(tester);
      return c;
    }

    testAppWidgets('logging hours: the rate is saved for the client', (
      tester,
    ) async {
      final c = await pump(tester);
      expect(find.text('Today, 5 Nov'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hours-log')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('hours-client')),
          matching: find.byType(TextField),
        ),
        'Bidii Traders Ltd',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('hours-project')),
          matching: find.byType(TextField),
        ),
        'Website revamp',
      );
      await tester.enterText(
        find.byKey(const Key('hours-what')),
        'Design review meeting',
      );
      await tester.enterText(find.byKey(const Key('hours-hours')), '1.5');
      await settleFrames(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('hours-rate')),
          matching: find.byType(TextField),
        ),
        '2500',
      );
      await tester.tap(find.byKey(const Key('hours-another')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hours-save')));
      await settleFrames(tester);
      // The sheet stays open for the next entry, with the rate remembered.
      expect(find.text('Log hours'), findsWidgets);
      expect(
        find.text('At 2,500 an hour, saved for Bidii Traders Ltd'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('hours-what')), 'Build');
      await tester.enterText(find.byKey(const Key('hours-hours')), '3.5');
      await tester.tap(find.byKey(const Key('hours-another')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hours-save')));
      await settleFrames(tester);

      final logged = await tester.runAsync(
        () => c
            .read(hoursRepositoryProvider)
            .between(CalendarDate(2026, 11, 2), CalendarDate(2026, 11, 9)),
      );
      expect(logged!.map((e) => e.minutes), [90, 210]);
      expect(logged.map((e) => e.rateMinor), [250000, 250000]);
      expect(find.text('Design review meeting'), findsOneWidget);
      expect(find.text('5 h'), findsWidgets);
      expect(find.text('Bidii 5 h'), findsOneWidget);
    });

    testAppWidgets('the week by project, and what it bills', (tester) async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        final repo = c.read(hoursRepositoryProvider);
        await repo.log(
          client: 'Bidii Traders Ltd',
          project: 'Website revamp',
          what: 'Build',
          day: CalendarDate(2026, 11, 3),
          minutes: 6 * 60,
          rateMinor: 250000,
          at: now,
        );
        await repo.log(
          client: 'Juhudi Sacco',
          project: 'Strategy',
          what: 'Travel to Juhudi',
          day: CalendarDate(2026, 11, 5),
          minutes: 60,
          billable: false,
          at: now,
        );
      });
      c.dispose();
      final screen = await pump(tester, week: true);
      expect(find.text('2 to 8 November'), findsOneWidget);
      expect(find.text('Tue 3 Nov'), findsOneWidget);
      expect(find.text('6 h × 2,500'), findsOneWidget);
      expect(find.text('15,000'), findsWidgets);
      expect(find.text('Not billed'), findsOneWidget);
      expect(find.text('7 h logged · 6 h to bill'), findsOneWidget);
      expect(screen, isNotNull);
    });
  });
}
