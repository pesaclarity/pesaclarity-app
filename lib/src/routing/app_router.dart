import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activity/presentation/activity_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/debts/presentation/debts_screen.dart';
import '../features/goals/presentation/goals_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/onboarding/presentation/my_accounts_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/privacy/presentation/privacy_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';

/// The app's router. Sends people to onboarding until it is complete.
final appRouterProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(onboardingControllerProvider));
  ref.listen(onboardingControllerProvider, (_, next) => onboarded.value = next);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final inOnboarding = state.matchedLocation.startsWith(
        AppRoutes.onboarding,
      );
      if (!onboarded.value && !inOnboarding) return AppRoutes.onboarding;
      if (onboarded.value && inOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'accounts',
            builder: (context, state) => const MyAccountsScreen(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const ProfileScreen(),
                    routes: [
                      GoRoute(
                        path: 'backup',
                        builder: (context, state) => const BackupScreen(),
                      ),
                      GoRoute(
                        path: 'privacy',
                        builder: (context, state) => const PrivacyScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                builder: (context, state) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.goals,
                builder: (context, state) => const GoalsScreen(),
                routes: [
                  GoRoute(
                    path: 'debts',
                    builder: (context, state) => const DebtsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.insights,
                builder: (context, state) => const InsightsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    onboarded.dispose();
  });
  return router;
});
