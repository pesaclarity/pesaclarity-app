import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/lending/data/reminder_sharer.dart';
import 'package:pesaclarity/src/features/lending/presentation/lending_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

/// 26 October 2026, 08:00 EAT.
final goalsTestNow = DateTime.utc(2026, 10, 26, 5);

/// Records shared reminders instead of opening the share sheet.
class FakeReminderSharer implements ReminderSharer {
  final shared = <String>[];

  @override
  Future<void> share(String message) async => shared.add(message);
}

/// Pumps the Goals tab and the screens under it on [db] at [location].
Future<void> pumpGoals(
  WidgetTester tester, {
  required AppDatabase db,
  String location = AppRoutes.goals,
  ReminderSharer? sharer,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.goals,
        builder: (context, state) => const GoalsScreen(),
        routes: [
          GoRoute(
            path: 'debts',
            builder: (context, state) =>
                const Scaffold(body: Text('Debts screen')),
          ),
          GoRoute(
            path: 'lending',
            builder: (context, state) => const LendingScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => goalsTestNow),
        reminderSharerProvider.overrideWithValue(
          sharer ?? FakeReminderSharer(),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await settle(tester);
}

/// Lets database work finish, then settles the frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}
