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

/// My accounts: an M-Pesa account set to USD (synthetic data).
void main() {
  late AppDatabase db;
  late int mpesa;

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
        'rates': {'KES': 129.2},
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
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            occurredAt: DateTime.utc(2026, 11, 3, 7, 42),
            amountMinor: 2500000,
            currency: const Value('KES'),
            direction: TransactionDirection.inflow,
            source: TransactionSource.sms,
            counterpartyName: const Value('Monthly pay'),
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
    await tester.tap(find.byKey(Key('account-currency-$mpesa')));
    await tester.pumpAndSettle();
    expect(find.text('M-Pesa currency'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('currency-search')), 'USD');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('currency-USD')));
    await tester.pumpAndSettle();
  }

  Future<String> currency() => DriftAccountsRepository(db).currencyOf(mpesa);

  testAppWidgets('lists each account in its currency', (tester) async {
    await pump(tester);
    expect(
      find.text(
        'Each account counts in its own currency. Totals add them up in '
        'your base currency, USD.',
      ),
      findsOneWidget,
    );
    expect(find.text('M-Pesa'), findsOneWidget);
    expect(find.text('Messages from MPESA'), findsOneWidget);
    expect(find.text('KES'), findsOneWidget);
    expect(find.text('Add or remove accounts'), findsOneWidget);
  });

  testAppWidgets('marks the transactions in the new currency', (tester) async {
    await pump(tester);
    await pickUsd(tester);
    expect(find.text('Count M-Pesa in USD?'), findsOneWidget);
    expect(
      find.text(
        "Its 1 transaction keeps its amount and is marked USD, as M-Pesa's "
        'messages show it. New messages from M-Pesa count in USD.',
      ),
      findsOneWidget,
    );
    expect(find.text('KES 25,000.00 → USD 25,000.00'), findsOneWidget);
    expect(
      find.text('Totals in your base currency, USD, change to match.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('account-currency-mark')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(currency), 'USD');
    expect(find.text('My accounts'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
  });

  testAppWidgets('keeps the currency', (tester) async {
    await pump(tester);
    await pickUsd(tester);
    await tester.tap(find.byKey(const Key('account-currency-keep')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(currency), 'KES');
    expect(find.text('M-Pesa currency'), findsOneWidget);
  });
}
