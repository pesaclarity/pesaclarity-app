import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/reader/rule_reader.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/balances/presentation/balance_check_screen.dart';
import 'package:pesaclarity/src/features/balances/presentation/balances_screen.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/review/presentation/review_inbox_screen.dart';
import 'package:pesaclarity/src/features/review/presentation/review_message_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';

/// Saturday 14 November 2026, 10:00 in Nairobi.
final scenarioNow = eat(2026, 11, 14, 10);

/// Ids of the scenario's accounts.
typedef ScenarioAccounts = ({int mpesa, int kcb, int cash, int sacco});

/// The person's phone in synthetic data, as the bug report describes it:
/// M-Pesa holds 0 after Fuliza paid for more than it held, so 1,300 is
/// owed to Fuliza; KCB holds 50 after sending M-Pesa 3,920 (fee 30); cash
/// is 100; a SACCO holds 13,500 in savings. One M-Pesa payment was counted
/// twice (a message and a statement), and three messages wait to be
/// checked, one of them KCB sending M-Pesa money.
Future<ScenarioAccounts> seedScenario(AppDatabase db) async {
  Future<int> account(
    String name,
    AccountType type, {
    String? institution,
    int opening = 0,
  }) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingDate: eat(2026, 11, 1, 0),
          openingBalanceMinor: Value(opening),
          institutionId: Value(institution),
        ),
      );
  final mpesa = await account(
    'M-Pesa',
    AccountType.mpesa,
    institution: 'mpesa',
  );
  final kcb = await account('KCB', AccountType.bank, institution: 'kcb');
  final cash = await account('Cash', AccountType.cash, opening: kes(100));
  final sacco = await account(
    'Example Sacco',
    AccountType.sacco,
    opening: kes(13500),
  );

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount, {
    TransactionDirection direction = TransactionDirection.outflow,
    TransactionKind kind = TransactionKind.till,
    int? balance,
    int fee = 0,
    String? name,
    TransactionSource source = TransactionSource.sms,
    int? owed,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    direction: direction,
    kind: Value(kind),
    feeMinor: Value(fee),
    counterpartyName: Value(name),
    source: source,
    dedupeKey: Value('seed-${n++}'),
    receiptNo: Value('TST000000$n'),
    balanceAfterMinor: Value(balance),
    owedAfterMinor: Value(owed),
  );

  final transactions = DriftTransactionsRepository(db);
  await transactions.addNew([
    tx(
      mpesa,
      eat(2026, 11, 10, 9, 12),
      kes(100),
      name: 'Example Kiosk',
      balance: kes(5800),
    ),
    tx(mpesa, eat(2026, 11, 11), kes(1200), name: 'Example Grocers'),
    tx(
      mpesa,
      eat(2026, 11, 11),
      kes(1200),
      name: 'Example Grocers',
      source: TransactionSource.statement,
    ),
    tx(
      mpesa,
      eat(2026, 11, 12, 10),
      kes(1180),
      kind: TransactionKind.paybill,
      name: 'Example Power',
      balance: kes(3420),
    ),
    // KCB sends M-Pesa 3,920; the two messages pair as one transfer.
    tx(
      kcb,
      eat(2026, 11, 13, 9),
      kes(3920),
      kind: TransactionKind.bank,
      fee: kes(30),
      balance: kes(50),
    ),
    tx(
      mpesa,
      eat(2026, 11, 13, 9, 3),
      kes(3920),
      direction: TransactionDirection.inflow,
      kind: TransactionKind.received,
      name: 'KCB',
      balance: kes(7340),
    ),
    // Paying 8,627.13 with 7,340 in M-Pesa: Fuliza covers the rest.
    tx(
      mpesa,
      eat(2026, 11, 13, 18, 40),
      862713,
      kind: TransactionKind.paybill,
      name: 'Example Landlord',
      balance: 0,
    ),
    tx(
      mpesa,
      eat(2026, 11, 13, 18, 40).add(const Duration(seconds: 20)),
      128713,
      direction: TransactionDirection.inflow,
      kind: TransactionKind.fulizaDraw,
      fee: 1287,
      owed: kes(1300),
    ),
  ]);

  for (final (i, (sender, institution, body)) in [
    (
      'KCB',
      'kcb',
      'KES 2,000.00 sent from 0000****001 to MPESA 0700 000 000 on '
          '14/11/26 at 09:02. Ref TST0000099.',
    ),
    (
      'MPESA',
      'mpesa',
      'Dear Customer, KES 350.00 has been paid to EXAMPLE CAFE on 14/11/26 '
          'at 08:30. Ref TST0000098.',
    ),
    (
      'MPESA',
      'mpesa',
      'Dear Customer, KES 2,000.00 has been received from KCB on 14/11/26 '
          'at 09:04. Ref TST0000097.',
    ),
  ].indexed) {
    await db
        .into(db.reviewItems)
        .insert(
          ReviewItemsCompanion.insert(
            institutionId: institution,
            sender: sender,
            receivedAt: eat(2026, 11, 14, 8, 30 + i),
            messageHash: 'seed-review-$i',
            body: Value(body),
            reason: 'no rule matched',
          ),
        );
  }
  return (mpesa: mpesa, kcb: kcb, cash: cash, sacco: sacco);
}

/// Pumps [location] on [db] with the screens this feature touches.
Future<ProviderContainer> pumpBalances(
  WidgetTester tester,
  AppDatabase db,
  String location, {
  ThemeData? theme,
  Size size = const Size(1000, 2400),
  double ratio = 2.5,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => scenarioNow),
      messageReaderProvider.overrideWith(
        (ref) async => const RuleMessageReader(),
      ),
    ],
  );
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'review',
            builder: (_, _) => const ReviewInboxScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ReviewMessageScreen(
                  itemId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'profile',
            builder: (_, _) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'balances',
                builder: (_, _) => const BalancesScreen(),
                routes: [
                  GoRoute(
                    path: 'check',
                    builder: (_, _) => const BalanceCheckScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.activity,
        builder: (_, state) => ActivityScreen(
          initialFilter: ActivityFilter.fromQuery(state.uri.queryParameters),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await settle(tester);
  return c;
}

/// Lets database queries finish, then the frames that follow them.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }
}
