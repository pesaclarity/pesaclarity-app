import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sacco_repository.dart';
import 'package:pesaclarity/src/features/accounts/presentation/account_page.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/accounts/presentation/sacco_screens.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

// Made-up accounts, SACCO and amounts.

void main() {
  late AppDatabase db;
  late int cash;
  late int oldBank;
  final now = eat(2026, 11, 22, 9, 41);

  setUp(() async {
    db = openTestDatabase();
    cash = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            openingDate: eat(2026, 1, 1),
            openingBalanceMinor: Value(kes(3500)),
          ),
        );
    oldBank = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Old KCB',
            type: AccountType.bank,
            openingDate: eat(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now),
          deviceRegionProvider.overrideWithValue('KE'),
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
    await settleFrames(tester);
    await tester.pumpAndSettle();
  }

  testAppWidgets('rows open the account; renaming and hiding save', (
    tester,
  ) async {
    await pump(tester, const MyAccountsSettingsScreen());
    expect(find.text('Add a SACCO'), findsOneWidget);
    await tester.tap(find.byKey(Key('account-row-$cash')));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text(AccountEditText.countOnHand), findsOneWidget);
    await tester.enterText(find.byKey(const Key('account-name')), 'Wallet');
    await tester.tap(find.byKey(const Key('account-hide')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-save')));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    final row = await tester.runAsync(
      () =>
          (db.select(db.accounts)..where((a) => a.id.equals(cash))).getSingle(),
    );
    expect(row!.name, 'Wallet');
    expect(row.hidden, isTrue);
    expect(find.byKey(Key('account-row-$cash')), findsNothing);
    expect(find.byKey(const Key('hidden-accounts')), findsOneWidget);
  });

  testAppWidgets('an account with nothing on it is removed after one '
      'question', (tester) async {
    await pump(tester, AccountPage(accountId: oldBank));
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-remove')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(const Key('account-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-remove')));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text('Remove Old KCB?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    final left = await tester.runAsync(() => db.select(db.accounts).get());
    expect(left!.map((a) => a.id), [cash]);
  });

  testAppWidgets('with transactions, nothing is chosen until tapped', (
    tester,
  ) async {
    await tester.runAsync(
      () => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: oldBank,
              occurredAt: eat(2026, 3, 1),
              amountMinor: kes(100),
              direction: TransactionDirection.inflow,
              source: TransactionSource.manual,
            ),
          ),
    );
    await pump(tester, AccountPage(accountId: oldBank));
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-remove')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(const Key('account-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-remove')));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text(AccountEditText.hideKeep), findsOneWidget);
    FilledButton go() => tester.widget(find.byKey(const Key('remove-go')));
    expect(go().onPressed, isNull);
    await tester.tap(find.byKey(const Key('remove-hide')));
    await tester.pumpAndSettle();
    expect(find.text('Hide Old KCB'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-move')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-move-to')), findsOneWidget);
    expect(go().onPressed, isNull);
  });

  testAppWidgets('a SACCO page shows saved, the loan and recent', (
    tester,
  ) async {
    final id = await tester.runAsync(
      () => SaccoRepository(db).add(
        name: 'Mwangaza SACCO',
        currency: 'KES',
        paybill: '400222',
        depositsMinor: kes(84000),
        sharesMinor: kes(20000),
        contributionMinor: kes(3000),
        borrowTimesTenths: 30,
        at: eat(2026, 10, 1, 9),
        loan: SaccoLoanInput(
          owedMinor: kes(150000),
          monthlyMinor: kes(6500),
          rateBasisPoints: 1200,
          checkOffDay: 28,
        ),
      ),
    );
    await pump(tester, SaccoScreen(accountId: id!));
    expect(find.text('104,000'), findsOneWidget);
    expect(find.text('Deposits 84,000 · shares 20,000'), findsOneWidget);
    expect(find.byKey(const Key('sacco-loan-row')), findsOneWidget);
    // 28 Oct's check-off came off the loan.
    expect(find.text('143,500'), findsOneWidget);
    expect(find.textContaining('check-off from salary'), findsOneWidget);
    expect(find.byKey(const Key('sacco-can-borrow')), findsOneWidget);
  });
}
