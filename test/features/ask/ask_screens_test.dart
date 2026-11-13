import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/application/ask_settings.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_conversations_screen.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_entry.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_screen.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_settings_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import 'ask_data_test.dart' show seedAsk;

/// Ask's screens on [db], starting at [location], with [home] as the page
/// the Ask bar sits on.
Future<ProviderContainer> pumpAsk(
  WidgetTester tester,
  AppDatabase db, {
  String location = AppRoutes.ask,
  Widget? home,
}) async {
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => eat(2026, 11, 13, 10)),
      askReaderRuntimeOpenerProvider.overrideWithValue(null),
    ],
  );
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(body: home ?? const SizedBox()),
      ),
      GoRoute(
        path: AppRoutes.ask,
        builder: (_, state) => AskScreen(
          categoryId: int.tryParse(state.uri.queryParameters['category'] ?? ''),
          from: parseCalendarDate(state.uri.queryParameters['from']),
          to: parseCalendarDate(state.uri.queryParameters['to']),
        ),
        routes: [
          GoRoute(
            path: 'conversations',
            builder: (_, _) => const AskConversationsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => AskScreen(
                  conversationId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const AskSettingsScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  return c;
}

Future<void> askQuestion(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const Key('ask-input')), q);
  await tester.tap(find.byKey(const Key('ask-send')));
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedAsk(db);
  });

  testAppWidgets('empty Ask shows the icon, words and suggestions', (
    tester,
  ) async {
    await pumpAsk(tester, db);
    expect(find.text('Ask about your money'), findsWidgets);
    expect(find.byKey(const Key('ask-starters')), findsOneWidget);
    await tester.tap(find.byTooltip('Hide suggestions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ask-starters')), findsNothing);
  });

  testAppWidgets('a question gets a bubble, an answer card and tags', (
    tester,
  ) async {
    await pumpAsk(tester, db);
    await askQuestion(tester, 'How much did I spend on food last month?');
    expect(
      find.text('How much did I spend on food last month?'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ask-answer')), findsOneWidget);
    expect(find.text('KES 10,230'), findsOneWidget);
    expect(find.text('Food · October 2026'), findsOneWidget);
    expect(find.text('Test Supermarket'), findsOneWidget);
    expect(find.byKey(const Key('ask-tag-category')), findsOneWidget);
    expect(find.text('Food spending last month'), findsOneWidget);

    // Dropping the month asks about this month.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('ask-tag-period')),
        matching: find.byIcon(Icons.close),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('ask-tag-period')), findsNothing);
  });

  testAppWidgets('outside the records: plain words and suggestions', (
    tester,
  ) async {
    await pumpAsk(tester, db);
    await askQuestion(tester, 'Should I buy a car?');
    expect(
      find.textContaining('I can only answer from your records'),
      findsOneWidget,
    );
    expect(find.text('These might help:'), findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets);
  });

  testAppWidgets('conversations list and the menu', (tester) async {
    await pumpAsk(tester, db);
    await askQuestion(tester, 'How much did I spend on food last month?');
    await tester.tap(find.byKey(const Key('ask-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Update all numbers'), findsOneWidget);
    expect(find.text('Delete conversation'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ask-conversations')));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Food spending last month'), findsOneWidget);
    expect(find.text('New conversation'), findsOneWidget);
  });

  testAppWidgets('settings: switches, keep-for drop-down, delete all', (
    tester,
  ) async {
    final c = await pumpAsk(tester, db, location: AppRoutes.askSettings);
    expect(find.text('Show Ask'), findsOneWidget);
    expect(find.text('Until I delete'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ask-show')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(c.read(askSettingsProvider).value!.show, isFalse);
    expect(find.textContaining('not in backups'), findsOneWidget);
  });

  testAppWidgets('the Ask bar hides on scroll and with Show Ask off', (
    tester,
  ) async {
    final c = await pumpAsk(
      tester,
      db,
      location: '/home',
      home: AskBarScope(
        child: ListView(
          children: [
            const AskHomeButton(),
            for (var i = 0; i < 60; i++) ListTile(title: Text('Row $i')),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('ask-bar')), findsOneWidget);
    expect(c.read(askBarAwayProvider), isFalse);
    await tester.drag(find.text('Row 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(c.read(askBarAwayProvider), isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(c.read(askBarAwayProvider), isFalse);

    await c
        .read(askSettingsProvider.notifier)
        .save(const AskSettings(show: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ask-bar')), findsNothing);
    expect(find.byKey(const Key('home-ask')), findsNothing);
  });

  test('Activity filters read as an Ask bar', () {
    final today = CalendarDate(2026, 11, 13);
    const food = Category(
      id: 4,
      name: 'Food',
      type: CategoryType.expense,
      isDailySpending: false,
    );
    final ask = askAboutFilter(
      ActivityFilter(
        categoryId: 4,
        from: CalendarDate(2026, 10, 1),
        to: CalendarDate(2026, 10, 27),
      ),
      {4: food},
      today,
    )!;
    expect(ask.$1, 'Ask about Food, 1 to 27 Oct');
    expect(ask.$2, contains('category=4'));
    expect(askAboutFilter(const ActivityFilter(), {4: food}, today), isNull);
  });

  testAppWidgets('Ask about a filter opens Ask with its tags', (tester) async {
    final id = (await db.select(db.categories).get())
        .firstWhere((c) => c.name == 'Food')
        .id;
    await pumpAsk(
      tester,
      db,
      location: AppRoutes.askAbout(
        categoryId: id,
        from: '2026-10-01',
        to: '2026-10-27',
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('ask-tag-category')), findsOneWidget);
    expect(find.text('1 to 27 Oct'), findsOneWidget);
    await askQuestion(tester, 'how much?');
    expect(find.text('KES 10,230'), findsOneWidget);
  });
}
