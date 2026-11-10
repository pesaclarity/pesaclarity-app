import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/database/database_providers.dart';
import '../domain/ledger/activity_feed.dart';
import '../features/accounts/presentation/choose_accounts_screen.dart';
import '../features/accounts/presentation/my_accounts_settings_screen.dart';
import '../features/activity/presentation/activity_screen.dart';
import '../features/auth/presentation/devices_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/backup_setup_screen.dart';
import '../features/books/presentation/money_screen.dart';
import '../features/business_insights/presentation/full_records_screen.dart';
import '../features/business_insights/presentation/insights_tab.dart';
import '../features/business_insights/presentation/make_report_screen.dart';
import '../features/close/presentation/close_day_screen.dart';
import '../features/currency/presentation/base_currency_screen.dart';
import '../features/currency/presentation/converter_screen.dart';
import '../features/currency/presentation/setup_currency_screen.dart';
import '../features/debts/presentation/debts_screen.dart';
import '../features/documents/presentation/document_settings_screen.dart';
import '../features/goals/presentation/goals_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/hours/presentation/hours_screen.dart';
import '../features/income/presentation/income_sources_screen.dart';
import '../features/income/presentation/week_by_week_screen.dart';
import '../features/invoices/presentation/invoices_screen.dart';
import '../features/invoices/presentation/make_invoice_screen.dart';
import '../features/lending/presentation/lending_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/onboarding/presentation/first_insight_screen.dart';
import '../features/onboarding/presentation/my_accounts_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/payees/presentation/payees_screen.dart';
import '../features/people/presentation/people_screen.dart';
import '../features/people/presentation/reminder_messages_screen.dart';
import '../features/people/presentation/statement_screen.dart';
import '../features/plan/presentation/payday_screen.dart';
import '../features/plan/presentation/plan_screen.dart';
import '../features/privacy/presentation/policy_screen.dart';
import '../features/privacy/presentation/privacy_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/review/presentation/review_inbox_screen.dart';
import '../features/review/presentation/review_message_screen.dart';
import '../features/sales/presentation/sell_screen.dart';
import '../features/security/application/app_lock_controller.dart';
import '../features/sms/presentation/connect_messages_screen.dart';
import '../features/sms/presentation/sms_scan_screen.dart';
import '../features/spaces/presentation/add_space_screen.dart';
import '../features/spaces/presentation/business_or_personal_screen.dart';
import '../features/spaces/presentation/business_setup_screens.dart';
import '../features/spaces/presentation/choose_space_screen.dart';
import '../features/statements/presentation/statement_import_screen.dart';
import '../features/stock/presentation/count_stock_screen.dart';
import '../features/stock/presentation/item_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import '../features/subscriptions/presentation/subscriptions_screen.dart';
import '../features/support/presentation/gifts_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/tax/presentation/tax_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'launch_screen.dart';

/// Whether onboarding is complete, read only once app lock has released the
/// database key; loading until then.
final launchGateProvider = Provider<AsyncValue<bool>>((ref) {
  final released = ref.watch(
    appLockControllerProvider.select((state) => state.keyReleased),
  );
  if (!released) return const AsyncLoading();
  return ref.watch(onboardingControllerProvider);
});

/// The app's router. Waits for unlock, then sends people to onboarding until
/// it is complete.
final appRouterProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<AsyncValue<bool>>(
    ref.read(launchGateProvider),
  );
  ref.listen(launchGateProvider, (_, next) => onboarded.value = next);

  final router = GoRouter(
    initialLocation: AppRoutes.launch,
    refreshListenable: onboarded,
    redirect: (context, state) => onboardingRedirect(
      onboarded.value,
      state.matchedLocation,
      askSpace: ref.read(spaceQuestionProvider),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.launch,
        builder: (context, state) => const LaunchScreen(),
      ),
      GoRoute(
        path: AppRoutes.chooseSpace,
        builder: (context, state) => const ChooseSpaceScreen(),
      ),
      GoRoute(
        path: AppRoutes.closeDay,
        builder: (context, state) => const CloseDayScreen(),
      ),
      GoRoute(
        path: AppRoutes.sell,
        builder: (context, state) =>
            SellScreen(billed: state.uri.queryParameters['for'] == 'billed'),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            path: 'currency',
            builder: (context, state) => const SetupCurrencyScreen(),
          ),
          GoRoute(
            path: 'income',
            builder: (context, state) =>
                const IncomeSourcesScreen(onboarding: true),
          ),
          GoRoute(
            path: 'accounts',
            builder: (context, state) => const MyAccountsScreen(),
            routes: [
              GoRoute(
                path: 'scan',
                // iPhone has no inbox to scan; it connects Shortcuts instead.
                builder: (context, state) =>
                    defaultTargetPlatform == TargetPlatform.iOS
                    ? const ConnectMessagesScreen(onboarding: true)
                    : const SmsScanScreen(),
                routes: [
                  GoRoute(
                    path: 'insight',
                    builder: (context, state) => const FirstInsightScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Branches in [ShellBranch] order.
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
                    path: 'review',
                    builder: (context, state) => const ReviewInboxScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) => ReviewMessageScreen(
                          itemId: int.parse(state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'import',
                    builder: (context, state) => const StatementImportScreen(),
                  ),
                  GoRoute(
                    path: 'week',
                    builder: (context, state) => const WeekByWeekScreen(),
                  ),
                  GoRoute(
                    path: 'spaces/add',
                    builder: (context, state) => const AddSpaceScreen(),
                  ),
                  GoRoute(
                    path: 'spaces/sells',
                    builder: (context, state) => const WhatYouSellScreen(),
                  ),
                  GoRoute(
                    path: 'spaces/start',
                    builder: (context, state) => const StartRecordsScreen(),
                  ),
                  GoRoute(
                    path: 'spaces/routing',
                    builder: (context, state) =>
                        const BusinessOrPersonalScreen(),
                  ),
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const ProfileScreen(),
                    routes: [
                      GoRoute(
                        path: 'accounts',
                        builder: (context, state) =>
                            const MyAccountsSettingsScreen(),
                        routes: [
                          GoRoute(
                            path: 'choose',
                            builder: (context, state) =>
                                const ChooseAccountsScreen(),
                          ),
                        ],
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
                        routes: [
                          GoRoute(
                            path: 'policy',
                            builder: (context, state) => const PolicyScreen(),
                          ),
                          GoRoute(
                            path: 'terms',
                            builder: (context, state) => const TermsScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'connect',
                        builder: (context, state) =>
                            const ConnectMessagesScreen(),
                      ),
                      GoRoute(
                        path: 'payees',
                        builder: (context, state) => const PayeesScreen(),
                      ),
                      GoRoute(
                        path: 'currency',
                        builder: (context, state) => const BaseCurrencyScreen(),
                        routes: [
                          GoRoute(
                            path: 'converter',
                            builder: (context, state) =>
                                const ConverterScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'income',
                        builder: (context, state) =>
                            const IncomeSourcesScreen(),
                      ),
                      GoRoute(
                        path: 'support',
                        builder: (context, state) => const SupportScreen(),
                        routes: [
                          GoRoute(
                            path: 'gifts',
                            builder: (context, state) => const GiftsScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'subscriptions',
                        builder: (context, state) =>
                            const SubscriptionsScreen(),
                      ),
                      GoRoute(
                        path: 'documents',
                        builder: (context, state) =>
                            const DocumentSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'sign-in',
                        builder: (context, state) => const SignInScreen(),
                      ),
                      GoRoute(
                        path: 'devices',
                        builder: (context, state) => const DevicesScreen(),
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
                builder: (context, state) => ActivityScreen(
                  // A new filter from another tab starts a fresh screen.
                  key: ValueKey(state.uri.query),
                  initialFilter: ActivityFilter.fromQuery(
                    state.uri.queryParameters,
                  ),
                ),
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
                  GoRoute(
                    path: 'lending',
                    builder: (context, state) => const LendingScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.insights,
                builder: (context, state) => const InsightsTab(),
                routes: [
                  GoRoute(
                    path: 'records',
                    builder: (context, state) => const FullRecordsScreen(),
                  ),
                  GoRoute(
                    path: 'report',
                    builder: (context, state) => const MakeReportScreen(),
                  ),
                  GoRoute(
                    path: 'tax',
                    builder: (context, state) => const TaxScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.money,
                builder: (context, state) => const MoneyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.people,
                builder: (context, state) => const PeopleScreen(),
                routes: [
                  GoRoute(
                    path: 'customer',
                    builder: (context, state) => CustomerStatementScreen(
                      name: state.uri.queryParameters['name'] ?? '',
                    ),
                  ),
                  GoRoute(
                    path: 'messages',
                    builder: (context, state) => const ReminderMessagesScreen(),
                  ),
                  GoRoute(
                    path: 'invoices',
                    builder: (context, state) => const InvoicesScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => MakeInvoiceScreen(
                          client: state.uri.queryParameters['client'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'supplier/:id',
                    builder: (context, state) => SupplierStatementScreen(
                      debtId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.stock,
                builder: (context, state) => const StockScreen(),
                routes: [
                  GoRoute(
                    path: 'item/:id',
                    builder: (context, state) => ItemScreen(
                      itemId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                  GoRoute(
                    path: 'count',
                    builder: (context, state) => const CountStockScreen(),
                  ),
                  GoRoute(
                    path: 'hours',
                    builder: (context, state) => HoursScreen(
                      week: state.uri.queryParameters['view'] == 'week',
                    ),
                  ),
                ],
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
String? onboardingRedirect(
  AsyncValue<bool> onboarded,
  String location, {
  bool askSpace = false,
}) {
  if (!onboarded.hasValue && !onboarded.hasError) {
    return location == AppRoutes.launch ? null : AppRoutes.launch;
  }
  final complete = onboarded.value ?? false;
  final inOnboarding = location.startsWith(AppRoutes.onboarding);
  if (!complete) return inOnboarding ? null : AppRoutes.onboarding;
  if (inOnboarding || location == AppRoutes.launch) {
    return askSpace ? AppRoutes.chooseSpace : AppRoutes.home;
  }
  return null;
}
