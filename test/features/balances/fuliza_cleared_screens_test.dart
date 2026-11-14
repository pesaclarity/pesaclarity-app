import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import 'balances_harness.dart';

/// The M-Pesa sheet in the bug report, in synthetic data: a payment took
/// M-Pesa to 0 and Fuliza covered it, 490.07 owed in all; this morning
/// 7,333.80 came in and M-Pesa repaid Fuliza first, leaving 6,843.73.
/// [money] adds the money in, [repayment] its "fully pay" message.
Future<int> seedFuliza(
  AppDatabase db, {
  bool money = true,
  bool repayment = true,
}) async {
  final mpesa = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: eat(2026, 11, 1, 0),
          institutionId: const Value('mpesa'),
        ),
      );
  var n = 0;
  TransactionsCompanion tx(
    DateTime at,
    int amount, {
    TransactionDirection direction = TransactionDirection.outflow,
    TransactionKind kind = TransactionKind.paybill,
    int? balance,
    int fee = 0,
    int? owed,
    String? name,
  }) => TransactionsCompanion.insert(
    accountId: mpesa,
    occurredAt: at,
    amountMinor: amount,
    direction: direction,
    kind: Value(kind),
    feeMinor: Value(fee),
    counterpartyName: Value(name),
    source: TransactionSource.sms,
    dedupeKey: Value('fuliza-${n++}'),
    receiptNo: Value('TST000040$n'),
    balanceAfterMinor: Value(balance),
    owedAfterMinor: Value(owed),
  );
  await DriftTransactionsRepository(db).addNew([
    tx(eat(2026, 11, 13, 18, 40), kes(900), balance: kes(500)),
    tx(eat(2026, 11, 13, 19), kes(985), name: 'EXAMPLE SHOP', balance: 0),
    tx(
      eat(2026, 11, 13, 19).add(const Duration(seconds: 20)),
      48522,
      direction: TransactionDirection.inflow,
      kind: TransactionKind.fulizaDraw,
      fee: 485,
      owed: 49007,
    ),
    if (money)
      tx(
        eat(2026, 11, 14, 8, 19),
        733380,
        direction: TransactionDirection.inflow,
        kind: TransactionKind.received,
        name: 'EXAMPLE PERSON',
        balance: 684373,
      ),
    if (money && repayment)
      tx(
        eat(2026, 11, 14, 8, 19).add(const Duration(seconds: 40)),
        49007,
        kind: TransactionKind.fulizaRepayment,
        balance: 684373,
      ),
  ]);
  return mpesa;
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());

  Future<List<TransactionRecord>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.transactions).get()))!;

  for (final repayment in [true, false]) {
    testAppWidgets(
      'after the repayment${repayment ? '' : ' (no message for it)'} '
      'M-Pesa shows 6,843.73 and no Fuliza',
      (tester) async {
        final mpesa = (await tester.runAsync(
          () => seedFuliza(db, repayment: repayment),
        ))!;
        await pumpBalances(tester, db, AppRoutes.balances);
        expect(find.textContaining('Fuliza owed'), findsNothing);
        expect(find.text('Matches'), findsOneWidget);
        expect(find.textContaining('Off by'), findsNothing);
        await tester.tap(find.byKey(Key('balance-account-$mpesa')));
        await settle(tester);
        expect(find.text('KES 6,843.73'), findsWidgets);
        expect(find.byKey(const Key('fuliza-is-paid')), findsNothing);
      },
    );
  }

  testAppWidgets('Activity says the money in repaid Fuliza automatically', (
    tester,
  ) async {
    await tester.runAsync(() => seedFuliza(db, repayment: false));
    await pumpBalances(tester, db, AppRoutes.activity);
    expect(
      find.textContaining('Fuliza repaid automatically: KES 490.07'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
  });

  testAppWidgets('Fuliza is paid on the M-Pesa sheet, and undo', (
    tester,
  ) async {
    final mpesa = (await tester.runAsync(() => seedFuliza(db, money: false)))!;
    await pumpBalances(tester, db, AppRoutes.balances);
    expect(find.textContaining('490.07 Fuliza owed'), findsOneWidget);
    await tester.tap(find.byKey(Key('balance-account-$mpesa')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('fuliza-is-paid')));
    await settle(tester);

    final paid = (await rows(tester))
        .singleWhere((r) => r.kind == TransactionKind.correction);
    expect(paid.item, fulizaPaidNote);
    expect(paid.balanceAfterMinor, 0);
    expect(paid.amountMinor, 49007);
    expect(find.textContaining('Fuliza owed'), findsNothing);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(
      (await rows(tester)).where((r) => r.kind == TransactionKind.correction),
      isEmpty,
    );
    expect(find.textContaining('490.07 Fuliza owed'), findsOneWidget);
  });

  testAppWidgets('Fuliza is paid on the Debts card', (tester) async {
    await tester.runAsync(() => seedFuliza(db, money: false));
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => scenarioNow),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const DebtsScreen()),
      ),
    );
    await settle(tester);
    expect(find.byKey(const Key('debts-fuliza-owed')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('fuliza-is-paid')));
    await tester.tap(find.byKey(const Key('fuliza-is-paid')));
    await settle(tester);
    expect(find.byKey(const Key('debts-fuliza-owed')), findsNothing);
    expect(
      (await rows(tester)).where((r) => r.kind == TransactionKind.correction),
      hasLength(1),
    );
  });
}
