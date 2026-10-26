import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/presentation/my_accounts_settings_screen.dart';
import '../features/activity/presentation/activity_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/backup_setup_screen.dart';
import '../features/debts/presentation/debts_screen.dart';
import '../features/goals/presentation/goals_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/onboarding/presentation/my_accounts_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/plan/presentation/payday_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/privacy/presentation/privacy_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/sms/presentation/sms_scan_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'launch_screen.dart';

/// The app's router. Sends people to onboarding until it is complete.
final appRouterProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<AsyncValue<bool>>(
    ref.read(onboardingControllerProvider),
  );
  ref.listen(onboardingControllerProvider, (_, next) => onboarded.value = next);

  final router = GoRouter(
    initialLocation: AppRoutes.launch,
    refreshListenable: onboarded,
    redirect: (context, state) =>
        onboardingRedirect(onboarded.value, state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.launch,
        builder: (context, state) => const LaunchScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'accounts',
            builder: (context, state) => const MyAccountsScreen(),
            routes: [
              GoRoute(
                path: 'scan',
                builder: (context, state) => const SmsScanScreen(),
              ),
            ],
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
                        path: 'accounts',
                        builder: (context, state) =>
                            const MyAccountsSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'backup',
                        builder: (context, state) => const BackupScreen(),
                        routes: [
                          GoRoute(
                            path: 'setup',
                            builder: (context, state) =>
                                const BackupSetupScreen(),
                          ),
                        ],
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
                routes: [
                  GoRoute(
                    path: 'payday',
                    builder: (context, state) => const PaydayScreen(),
                  ),
                ],
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

/// Where to send someone at [location] given the saved onboarding state.
///
/// Waits on the launch screen while the state loads; a failed read shows
/// onboarding rather than skipping it.
String? onboardingRedirect(AsyncValue<bool> onboarded, String location) {
  if (!onboarded.hasValue && !onboarded.hasError) {
    return location == AppRoutes.launch ? null : AppRoutes.launch;
  }
  final complete = onboarded.value ?? false;
  final inOnboarding = location.startsWith(AppRoutes.onboarding);
  if (!complete) return inOnboarding ? null : AppRoutes.onboarding;
  if (inOnboarding || location == AppRoutes.launch) return AppRoutes.home;
  return null;
}
