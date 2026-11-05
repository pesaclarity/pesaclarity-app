import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/business_setup.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/business_setup_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/business_setup_screens.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 20, 9);

  setUp(() {
    db = openTestDatabase();
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    deviceRegionProvider.overrideWithValue('KE'),
  ];

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    return c;
  }

  Future<int> mpesa() async {
    final id = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 10, 1, 0),
            institutionId: const Value('mpesa'),
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: id,
            occurredAt: eat(2026, 11, 19),
            amountMinor: kes(500),
            direction: TransactionDirection.inflow,
            balanceAfterMinor: Value(kes(8200)),
            source: TransactionSource.sms,
          ),
        );
    return id;
  }

  test('setup is saved with the space and starts the books today', () async {
    final account = await mpesa();
    final c = container();
    expect((await c.read(businessSetupProvider.future)).isDone, isFalse);

    final lines = await c.read(openingLinesProvider.future);
    expect(lines.single.accountId, account);
    expect(lines.single.suggestedMinor, kes(8200));
    expect(lines.single.fromMessage, isTrue);

    final setup = c.read(businessSetupProvider.notifier);
    await setup.chooseSells(BusinessSells.services);
    await setup.startRecords(
      cashMinor: kes(1000),
      accounts: {account: kes(8200)},
    );

    final done = await c.read(businessSetupProvider.future);
    expect(done.sells, BusinessSells.services);
    expect(done.isDone, isTrue);
    final accounts = await db.select(db.accounts).get();
    final cash = accounts.singleWhere((a) => a.type == AccountType.cash);
    expect(cash.name, cashAccountName);
    expect(cash.openingBalanceMinor, kes(1000));
    final m = accounts.singleWhere((a) => a.id == account);
    expect(m.openingBalanceMinor, kes(8200));
    expect(m.openingDate.isAtSameMomentAs(eat(2026, 11, 20, 0)), isTrue);

    // Starting again reuses the same drawer.
    await setup.startRecords(cashMinor: kes(1500), accounts: const {});
    final again = await db.select(db.accounts).get();
    expect(again.where((a) => a.type == AccountType.cash), hasLength(1));
    expect(BusinessSetup.fromJson(done.toJson()).sells, BusinessSells.services);
  });

  testAppWidgets('choosing what the business sells, then its records', (
    tester,
  ) async {
    await tester.runAsync(mpesa);
    final router = GoRouter(
      initialLocation: AppRoutes.whatYouSell,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, _) => const Text('Home')),
        GoRoute(
          path: AppRoutes.whatYouSell,
          builder: (_, _) => const WhatYouSellScreen(),
        ),
        GoRoute(
          path: AppRoutes.startRecords,
          builder: (_, _) => const StartRecordsScreen(),
        ),
      ],
    );
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    // Database work runs outside the test's fake clock, so let it finish
    // between frames instead of waiting for the screen to settle.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await settleFrames(tester);
    expect(find.text('With Products you get'), findsOneWidget);
    await tester.tap(find.text('Services'));
    await settleFrames(tester);
    expect(find.textContaining('No stock'), findsWidgets);
    await tester.tap(find.byKey(const Key('sells-continue')));
    await settleFrames(tester);

    expect(find.text('Start your records'), findsOneWidget);
    expect(
      find.text('We filled this in from your latest message.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('start-cash')), '1000');
    await tester.tap(find.byKey(const Key('start-records')));
    await settleFrames(tester);
    expect(find.text('Home'), findsOneWidget);

    final setup = await tester.runAsync(
      () => c.read(businessSetupProvider.future),
    );
    expect(setup!.sells, BusinessSells.services);
    expect(setup.isDone, isTrue);
  });
}
