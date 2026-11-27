import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/database/database_providers.dart';
import '../domain/ledger/activity_feed.dart';
import '../domain/time/calendar.dart';
import '../features/accounts/presentation/choose_accounts_screen.dart';
import '../features/accounts/presentation/my_accounts_settings_screen.dart';
import '../features/activity/presentation/activity_screen.dart';
import '../features/ask/presentation/ask_conversations_screen.dart';
import '../features/ask/presentation/ask_screen.dart';
import '../features/ask/presentation/ask_settings_screen.dart';
import '../features/auth/presentation/devices_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/backup_setup_screen.dart';
import '../features/balances/presentation/balance_check_screen.dart';
import '../features/balances/presentation/balances_screen.dart';
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
import '../features/firefly/presentation/firefly_screen.dart';
import '../features/goals/presentation/goals_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/more_this_month_screen.dart';
import '../features/home/presentation/things_to_sort_screen.dart';
import '../features/hours/presentation/hours_screen.dart';
import '../features/income/presentation/income_sources_screen.dart';
import '../features/income/presentation/week_by_week_screen.dart';
import '../features/insights/presentation/category_breakdown_screen.dart';
import '../features/invoices/presentation/invoices_screen.dart';
import '../features/invoices/presentation/make_invoice_screen.dart';
import '../features/lending/presentation/lending_screen.dart';
import '../features/onboarding/application/onboarding_controller.dart';
import '../features/onboarding/presentation/about_you_screen.dart';
import '../features/onboarding/presentation/first_insight_screen.dart';
import '../features/onboarding/presentation/my_accounts_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/payees/presentation/categories_screen.dart';
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
import '../features/sharing/presentation/approval_screens.dart';
import '../features/sharing/presentation/share_screens.dart';
import '../features/sms/presentation/connect_messages_screen.dart';
import '../features/sms/presentation/paste_messages_screen.dart';
import '../features/sms/presentation/sms_scan_screen.dart';
import '../features/spaces/application/spaces_providers.dart';
import '../features/spaces/presentation/add_space_screen.dart';
import '../features/spaces/presentation/business_or_personal_screen.dart';
import '../features/spaces/presentation/business_setup_screens.dart';
import '../features/spaces/presentation/choose_space_screen.dart';
import '../features/spaces/presentation/manage_spaces_screens.dart';
import '../features/statements/presentation/statement_import_screen.dart';
import '../features/stock/presentation/count_stock_screen.dart';
import '../features/stock/presentation/item_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import '../features/subscriptions/presentation/subscriptions_screen.dart';
import '../features/support/presentation/gifts_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/tax/presentation/tax_screen.dart';
import 'app_page.dart';
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
  // Nothing opens the space to open until it is known to be on the list.
  final checked = ref.watch(openSpaceCheckProvider);
  if (checked.isLoading && !checked.hasValue) return const AsyncLoading();
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
      AppRoute(
        path: AppRoutes.launch,
        builder: (context, state) => const LaunchScreen(),
      ),
      AppRoute(
        path: AppRoutes.chooseSpace,
        builder: (context, state) => const ChooseSpaceScreen(),
      ),
      AppRoute(
        path: AppRoutes.closeDay,
        builder: (context, state) => const CloseDayScreen(),
      ),
      AppRoute(
        path: AppRoutes.ask,
        builder: (context, state) => AskScreen(
          categoryId: int.tryParse(state.uri.queryParameters['category'] ?? ''),
          month: _yearMonth(state.uri.queryParameters['month']),
          from: parseCalendarDate(state.uri.queryParameters['from']),
          to: parseCalendarDate(state.uri.queryParameters['to']),
        ),
        routes: [
          AppRoute(
            path: 'conversations',
            builder: (context, state) => const AskConversationsScreen(),
            routes: [
              AppRoute(
                path: ':id',
                builder: (context, state) => AskScreen(
                  conversationId: int.tryParse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          AppRoute(
            path: 'settings',
            builder: (context, state) => const AskSettingsScreen(),
          ),
        ],
      ),
      AppRoute(
        path: AppRoutes.sell,
        builder: (context, state) =>
            SellScreen(billed: state.uri.queryParameters['for'] == 'billed'),
      ),
      AppRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          AppRoute(
            path: 'currency',
            builder: (context, state) => const SetupCurrencyScreen(),
          ),
          AppRoute(
            path: 'income',
            builder: (context, state) =>
                const IncomeSourcesScreen(onboarding: true),
          ),
          AppRoute(
            path: 'accounts',
            builder: (context, state) => const MyAccountsScreen(),
            routes: [
              AppRoute(
                path: 'scan',
                // iPhone has no inbox to scan; it connects Shortcuts instead.
                builder: (context, state) =>
                    defaultTargetPlatform == TargetPlatform.iOS
                    ? const ConnectMessagesScreen(onboarding: true)
                    : const SmsScanScreen(),
                routes: [
                  AppRoute(
                    path: 'insight',
                    builder: (context, state) => const FirstInsightScreen(),
                    routes: [
                      AppRoute(
                        path: 'about',
                        builder: (context, state) =>
                            const AboutYouScreen(onboarding: true),
                      ),
                    ],
                  ),
                  AppRoute(
                    path: 'paste',
                    builder: (context, state) =>
                        const PasteMessagesScreen(onboarding: true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Branches in [ShellBranch] order.
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            appPage(state, AppShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              AppRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
                routes: [
                  AppRoute(
                    path: 'review',
                    builder: (context, state) => const ReviewInboxScreen(),
                    routes: [
                      AppRoute(
                        path: ':id',
                        builder: (context, state) => ReviewMessageScreen(
                          itemId: int.parse(state.pathParameters['id']!),
                        ),
                      ),
                    ],
                  ),
                  AppRoute(
                    path: 'import',
                    builder: (context, state) => const StatementImportScreen(),
                  ),
                  AppRoute(
                    path: 'week',
                    builder: (context, state) => const WeekByWeekScreen(),
                  ),
                  AppRoute(
                    path: 'sort',
                    builder: (context, state) => const ThingsToSortScreen(),
                  ),

                  AppRoute(
                    path: 'spaces/add',
                    builder: (context, state) => const AddSpaceScreen(),
                  ),
                  AppRoute(
                    path: 'spaces/sells',
                    builder: (context, state) => const WhatYouSellScreen(),
                  ),
                  AppRoute(
                    path: 'spaces/start',
                    builder: (context, state) => const StartRecordsScreen(),
                  ),
                  AppRoute(
                    path: 'spaces/routing',
                    builder: (context, state) =>
                        const BusinessOrPersonalScreen(),
                  ),
                  AppRoute(
                    path: 'profile',
                    builder: (context, state) => const ProfileScreen(),
                    routes: [
                      AppRoute(
                        path: 'accounts',
                        builder: (context, state) =>
                            const MyAccountsSettingsScreen(),
                        routes: [
                          AppRoute(
                            path: 'choose',
                            builder: (context, state) =>
                                const ChooseAccountsScreen(),
                          ),
                          AppRoute(
                            path: 'paste',
                            builder: (context, state) =>
                                const PasteMessagesScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'balances',
                        builder: (context, state) => const BalancesScreen(),
                        routes: [
                          AppRoute(
                            path: 'check',
                            builder: (context, state) =>
                                const BalanceCheckScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'backup',
                        builder: (context, state) => const BackupScreen(),
                        routes: [
                          AppRoute(
                            path: 'setup',
                            builder: (context, state) =>
                                const BackupSetupScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'firefly',
                        builder: (context, state) => const FireflyScreen(),
                      ),
                      AppRoute(
                        path: 'privacy',
                        builder: (context, state) => const PrivacyScreen(),
                        routes: [
                          AppRoute(
                            path: 'policy',
                            builder: (context, state) => const PolicyScreen(),
                          ),
                          AppRoute(
                            path: 'terms',
                            builder: (context, state) => const TermsScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'about',
                        builder: (context, state) => const AboutYouScreen(),
                      ),
                      AppRoute(
                        path: 'connect',
                        builder: (context, state) =>
                            const ConnectMessagesScreen(),
                      ),
                      AppRoute(
                        path: 'payees',
                        builder: (context, state) => const PayeesScreen(),
                      ),
                      AppRoute(
                        path: 'categories',
                        builder: (context, state) => const CategoriesScreen(),
                        routes: [
                          AppRoute(
                            path: ':id',
                            builder: (context, state) => CategoryScreen(
                              categoryId: int.parse(
                                state.pathParameters['id']!,
                              ),
                            ),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'currency',
                        builder: (context, state) => const BaseCurrencyScreen(),
                        routes: [
                          AppRoute(
                            path: 'converter',
                            builder: (context, state) =>
                                const ConverterScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'income',
                        builder: (context, state) =>
                            const IncomeSourcesScreen(),
                      ),
                      AppRoute(
                        path: 'spaces',
                        builder: (context, state) => const SpacesScreen(),
                        routes: [
                          AppRoute(
                            path: 'deleted',
                            builder: (context, state) =>
                                const RecentlyDeletedScreen(),
                          ),
                          AppRoute(
                            path: 'delete-all',
                            builder: (context, state) =>
                                const DeleteAllScreen(),
                          ),
                          AppRoute(
                            path: 'join-request',
                            builder: (context, state) =>
                                const JoinRequestScreen(),
                          ),
                          AppRoute(
                            path: 'join',
                            builder: (context, state) =>
                                JoinSpaceScreen(invite: state.extra! as String),
                          ),
                          AppRoute(
                            path: ':id',
                            builder: (context, state) => SpaceSettingsScreen(
                              spaceId: state.pathParameters['id']!,
                            ),
                            routes: [
                              AppRoute(
                                path: 'clear',
                                builder: (context, state) => ClearSpaceScreen(
                                  spaceId: state.pathParameters['id']!,
                                ),
                              ),
                              AppRoute(
                                path: 'share',
                                builder: (context, state) => ShareSpaceScreen(
                                  spaceId: state.pathParameters['id']!,
                                ),
                                routes: [
                                  AppRoute(
                                    path: 'history',
                                    builder: (context, state) =>
                                        const SpaceHistoryScreen(),
                                  ),
                                  AppRoute(
                                    path: 'approvals',
                                    builder: (context, state) =>
                                        const ApprovalsScreen(),
                                  ),
                                  AppRoute(
                                    path: 'rules',
                                    builder: (context, state) =>
                                        const ShareRulesScreen(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'support',
                        builder: (context, state) => const SupportScreen(),
                        routes: [
                          AppRoute(
                            path: 'gifts',
                            builder: (context, state) => const GiftsScreen(),
                          ),
                        ],
                      ),
                      AppRoute(
                        path: 'subscriptions',
                        builder: (context, state) =>
                            const SubscriptionsScreen(),
                      ),
                      AppRoute(
                        path: 'documents',
                        builder: (context, state) =>
                            const DocumentSettingsScreen(),
                      ),
                      AppRoute(
                        path: 'sign-in',
                        builder: (context, state) => const SignInScreen(),
                      ),
                      AppRoute(
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
              AppRoute(
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
              AppRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const PlanScreen(),
                routes: [
                  AppRoute(
                    path: 'payday',
                    builder: (context, state) => const PaydayScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              AppRoute(
                path: AppRoutes.goals,
                builder: (context, state) => const GoalsScreen(),
                routes: [
                  AppRoute(
                    path: 'debts',
                    builder: (context, state) => const DebtsScreen(),
                  ),
                  AppRoute(
                    path: 'lending',
                    builder: (context, state) => const LendingScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              AppRoute(
                path: AppRoutes.insights,
                builder: (context, state) => const InsightsTab(),
                routes: [
                  AppRoute(
                    path: 'month',
                    builder: (context, state) => const MoreThisMonthScreen(),
                  ),
                  AppRoute(
                    path: 'records',
                    builder: (context, state) => const FullRecordsScreen(),
                  ),
                  AppRoute(
                    path: 'report',
                    builder: (context, state) => const MakeReportScreen(),
                  ),
                  AppRoute(
                    path: 'tax',
                    builder: (context, state) => const TaxScreen(),
                  ),
                  AppRoute(
                    path: 'category/:id',
                    builder: (context, state) => CategoryBreakdownScreen(
                      categoryId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              AppRoute(
                path: AppRoutes.money,
                builder: (context, state) => const MoneyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              AppRoute(
                path: AppRoutes.people,
                builder: (context, state) => const PeopleScreen(),
                routes: [
                  AppRoute(
                    path: 'customer',
                    builder: (context, state) => CustomerStatementScreen(
                      name: state.uri.queryParameters['name'] ?? '',
                    ),
                  ),
                  AppRoute(
                    path: 'messages',
                    builder: (context, state) => const ReminderMessagesScreen(),
                  ),
                  AppRoute(
                    path: 'invoices',
                    builder: (context, state) => const InvoicesScreen(),
                    routes: [
                      AppRoute(
                        path: 'new',
                        builder: (context, state) => MakeInvoiceScreen(
                          client: state.uri.queryParameters['client'],
                        ),
                      ),
                    ],
                  ),
                  AppRoute(
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
              AppRoute(
                path: AppRoutes.stock,
                builder: (context, state) => const StockScreen(),
                routes: [
                  AppRoute(
                    path: 'item/:id',
                    builder: (context, state) => ItemScreen(
                      itemId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                  AppRoute(
                    path: 'count',
                    builder: (context, state) => const CountStockScreen(),
                  ),
                  AppRoute(
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

/// `2026-10` as a month, or null.
YearMonth? _yearMonth(String? text) {
  final parts = text?.split('-');
  if (parts == null || parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  return YearMonth(year, month);
}
