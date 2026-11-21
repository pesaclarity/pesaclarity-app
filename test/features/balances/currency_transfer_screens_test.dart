// Currencies stage 2 on screen, as the approved mockups: the transfer as
// one line in Activity with the money in under the money out, each in its
// own currency; the transfer's sheet with the rate got, the day's rate and
// the cost; and money in another currency offered for matching by hand.
//
// Synthetic data only: invented accounts, numbers, amounts and rates. The
// day's rate is 1 USD = 129.20 KES.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/data/database/app_database.dart' hide Tag;
import 'package:pesaclarity/src/data/repositories/rate_history_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import 'balances_harness.dart';

void main() {
  late AppDatabase db;
  late int shillings;
  late int dollars;
  late int equity;

  Future<int> account(
    String name,
    String currency,
    int balance,
    String institution,
    String reference,
  ) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: AccountType.bank,
          currency: Value(currency),
          openingBalanceMinor: Value(balance),
          openingDate: eat(2026, 11, 1, 0),
          institutionId: Value(institution),
          reference: Value(reference),
        ),
      );

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount, {
    String currency = 'KES',
    bool inflow = false,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    currency: Value(currency),
    direction: inflow
        ? TransactionDirection.inflow
        : TransactionDirection.outflow,
    kind: const Value(TransactionKind.bank),
    source: TransactionSource.sms,
    dedupeKey: Value('s${n++}'),
  );

  setUp(() async {
    db = openTestDatabase();
    shillings = await account(
      'KCB ···4321',
      'KES',
      5000000,
      'kcb',
      '1100****4321',
    );
    dollars = await account('KCB ···8765', 'USD', 0, 'kcb', '1100****8765');
    equity = await account(
      'Equity Bank ···0002',
      'USD',
      0,
      'equity',
      '0170*****0002',
    );
    await DriftRateHistoryRepository(db).keep(
      CalendarDate(2026, 11, 14),
      ExchangeRates(
        base: 'KES',
        rates: const {'KES': 1, 'USD': 1 / 129.2},
        fetchedAt: eat(2026, 11, 14, 7),
      ),
    );
  });

  /// KES 13,050 out of KCB ···4321 at 09:00 and USD 100.00 into [to] at
  /// 09:02, as they arrive.
  Future<void> exchange(int to) async {
    final transactions = DriftTransactionsRepository(db);
    await transactions.addNew([tx(shillings, eat(2026, 11, 14, 9), 1305000)]);
    await transactions.addNew([
      tx(to, eat(2026, 11, 14, 9, 2), 10000, currency: 'USD', inflow: true),
    ]);
  }

  testAppWidgets('Activity: the transfer as one line, the money in under '
      'the money out; its sheet has the rate got, the day\'s rate and the '
      'cost', (tester) async {
    await tester.runAsync(() => exchange(dollars));
    await pumpBalances(tester, db, AppRoutes.activity);

    expect(find.text('KCB ···4321 → KCB ···8765'), findsOneWidget);
    expect(find.text('Own transfer · not spending'), findsOneWidget);
    expect(find.text('+KES 13,050'), findsOneWidget);
    expect(find.text('→ USD 100.00'), findsOneWidget);
    // Out this week is the exchange cost alone.
    expect(find.text('KES 130'), findsOneWidget);

    await tester.tap(find.text('KCB ···4321 → KCB ···8765'));
    await settle(tester);
    expect(find.text('Out of KCB ···4321'), findsOneWidget);
    expect(find.text('KES 13,050.00'), findsOneWidget);
    expect(find.text('Into KCB ···8765'), findsOneWidget);
    expect(find.text('USD 100.00'), findsOneWidget);
    expect(find.text('Rate you got'), findsOneWidget);
    expect(find.text('From the two amounts'), findsOneWidget);
    expect(find.text('1 USD = 130.50 KES'), findsOneWidget);
    expect(find.text("Day's rate"), findsOneWidget);
    expect(find.text('Rate of 14 Nov'), findsOneWidget);
    expect(find.text('1 USD = 129.20 KES'), findsOneWidget);
    expect(find.text('Exchange cost'), findsOneWidget);
    expect(
      find.text("1.0% over the day's rate · counts with fees"),
      findsOneWidget,
    );
    expect(find.text('KES 130.00'), findsOneWidget);
    expect(find.byKey(const Key('own-transfer-unmatch')), findsOneWidget);
  });

  testAppWidgets('Was this your own money? offers money in another currency '
      'in its own amount, with the rate the two give, and matches it', (
    tester,
  ) async {
    // Two banks: only offered, never paired by itself. The money out was
    // put under a category, so its line opens its sheet.
    await tester.runAsync(() async {
      await exchange(equity);
      final expense = await (db.select(
        db.categories,
      )..where((c) => c.type.equalsValue(CategoryType.expense))).get();
      await (db.update(
        db.transactions,
      )..where((t) => t.accountId.equals(shillings))).write(
        TransactionsCompanion(categoryOverrideId: Value(expense.first.id)),
      );
    });
    await pumpBalances(tester, db, AppRoutes.activity);
    await tester.tap(find.text('-KES 13,050'));
    await settle(tester);

    expect(find.text('Equity Bank ···0002, USD 100.00 in'), findsOneWidget);
    expect(find.textContaining('09:02 · 1 USD = 130.50 KES'), findsOneWidget);
    final rows = await tester.runAsync(() => db.select(db.transactions).get());
    final into = rows!.singleWhere((r) => r.accountId == equity);
    await tester.tap(find.byKey(Key('own-match-${into.id}')));
    await settle(tester);
    final after = await tester.runAsync(() => db.select(db.transactions).get());
    expect(after!.every((r) => r.transferPairId != null), isTrue);
    await tester.pump(const Duration(seconds: 10));
  });
}
