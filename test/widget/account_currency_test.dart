import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// My accounts: M-Pesa in KES from its messages, and Cash set by hand
/// (synthetic data).
void main() {
  late AppDatabase db;
  late int mpesa;
  late int cash;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(() => BaseCurrency.code = 'KES');
    final settings = DriftAppSettingsRepository(db);
    await settings.writeJson(CurrencyController.settingsKey, {
      'base': 'USD',
      'chosen': true,
      'ownRates': <String, Object?>{},
    });
    await settings.writeJson(
      CurrencyController.ratesKey,
      ExchangeRates.fromJson({
        'base': 'USD',
        'rates': {'KES': 129.2, 'SSP': 1000},
      }, fetchedAt: DateTime.utc(2026, 11, 3, 6))!.toJson(),
    );
    final accounts = DriftAccountsRepository(db);
    mpesa = await accounts.accountForInstitution(
      'mpesa',
      name: 'M-Pesa',
      type: AccountType.mpesa,
      openingDate: DateTime.utc(2026),
      currency: 'KES',
    );
    cash = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            currency: const Value('SSP'),
            openingDate: DateTime.utc(2026),
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: cash,
            occurredAt: DateTime.utc(2026, 11, 3, 7, 42),
            amountMinor: 2500000,
            currency: const Value('SSP'),
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
          ),
        );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ratesConfiguredProvider.overrideWithValue(false),
          deviceRegionProvider.overrideWithValue('SS'),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 3, 9)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MyAccountsSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickUsd(WidgetTester tester) async {
    await tester.tap(find.byKey(Key('account-currency-$cash')));
    await tester.pumpAndSettle();
    expect(find.text('Cash currency'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('currency-search')), 'USD');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('currency-USD')));
    await tester.pumpAndSettle();
  }

  Future<String> currency() => DriftAccountsRepository(db).currencyOf(cash);

  testAppWidgets('lists each account in its currency', (tester) async {
    await pump(tester);
    expect(
      find.text(
        'Each amount keeps the currency its message shows. Totals add them '
        'up in your base currency, USD.',
      ),
      findsOneWidget,
    );
    expect(find.text('Messages from MPESA'), findsOneWidget);
    expect(find.text('Money you add by hand'), findsOneWidget);
    // M-Pesa's currency comes from its messages: a label, not a button.
    await tester.tap(find.byKey(Key('account-currency-$mpesa')));
    await tester.pumpAndSettle();
    expect(find.text('M-Pesa currency'), findsNothing);
    expect(find.text('Add or remove accounts'), findsOneWidget);
  });

  testAppWidgets('new amounts in Cash take the new currency', (tester) async {
    await pump(tester);
    await pickUsd(tester);
    expect(find.text('Count Cash in USD?'), findsOneWidget);
    expect(
      find.text(
        'New amounts you add to Cash will be in USD. The 1 you added before '
        'stays in SSP.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('account-currency-use')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(currency), 'USD');
    final row = await tester.runAsync(
      () => db.select(db.transactions).getSingle(),
    );
    expect(row!.currency, 'SSP');
    expect(find.text('My accounts'), findsOneWidget);
  });

  testAppWidgets('keeps the currency', (tester) async {
    await pump(tester);
    await pickUsd(tester);
    await tester.tap(find.byKey(const Key('account-currency-keep')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(currency), 'SSP');
    expect(find.text('Cash currency'), findsOneWidget);
  });
}
