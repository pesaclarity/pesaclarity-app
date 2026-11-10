import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/add_transaction_sheet.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';
import 'package:pesaclarity/src/features/currency/presentation/converter_screen.dart';
import 'package:pesaclarity/src/features/sms/application/message_recheck.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// A person who counts in USD and pays from M-Pesa in KES (synthetic data).
void main() {
  late AppDatabase db;
  late int mpesaId;
  final now = DateTime.utc(2026, 11, 3, 9);
  final rates = ExchangeRates.fromJson({
    'base': 'USD',
    'rates': {'KES': 129.2, 'SSP': 1000},
  }, fetchedAt: DateTime.utc(2026, 11, 3, 6))!;

  setUp(() async {
    db = openTestDatabase();
    addTearDown(() => BaseCurrency.code = 'KES');
    final settings = DriftAppSettingsRepository(db);
    await settings.writeJson(CurrencyController.settingsKey, {
      'base': 'USD',
      'chosen': true,
      'ownRates': <String, Object?>{},
    });
    await settings.writeJson(CurrencyController.ratesKey, rates.toJson());
    final mpesa = mpesaId = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            currency: const Value('KES'),
            openingDate: DateTime.utc(2026),
          ),
        );
    final rent = await (db.select(
      db.categories,
    )..where((c) => c.type.equalsValue(CategoryType.expense))).get();
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            categoryOverrideId: Value(rent.first.id),
            occurredAt: DateTime.utc(2026, 11, 3, 7, 42),
            amountMinor: 2500000,
            currency: const Value('KES'),
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
            counterpartyName: const Value('Achieng Otieno'),
          ),
        );
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ratesConfiguredProvider.overrideWithValue(true),
          ratesSourceProvider.overrideWithValue(
            ratesSource('ExchangeRate-API', 'https://www.exchangerate-api.com'),
          ),
          deviceRegionProvider.overrideWithValue('SS'),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(theme: AppTheme.light, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testAppWidgets('Activity shows the KES first and the USD under it', (
    tester,
  ) async {
    await pump(tester, const ActivityScreen());
    expect(find.text('-KES 25,000'), findsOneWidget);
    expect(find.text('≈ USD 193.50'), findsOneWidget);
    expect(find.byKey(const Key('activity-currencies-note')), findsOneWidget);
    expect(
      find.text(
        'Totals are in USD, your base currency. KES amounts count at the '
        'rate of their day.',
      ),
      findsOneWidget,
    );

    // The payment: its day's rate, then the rate the person got.
    await tester.tap(find.text('Achieng Otieno'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-base-amount')), findsOneWidget);
    expect(find.text('1 USD = 129.2 KES'), findsOneWidget);
    expect(
      find.textContaining('The rate of 3 Nov, from ExchangeRate-API.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use the rate I got'));
    await tester.pumpAndSettle();
    expect(find.text('1 USD bought how much KES?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rate-got-field')), '129');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The rate you got for this payment.'), findsOneWidget);
    expect(find.text('≈ USD 193.80'), findsWidgets);

    await tester.tap(find.byKey(const Key('rate-day')));
    await tester.pumpAndSettle();
    expect(find.text('Use the rate I got'), findsOneWidget);
  });

  testAppWidgets('Activity hides amounts behind its eye', (tester) async {
    await pump(tester, const ActivityScreen());
    expect(find.text('-KES 25,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('amounts-eye')));
    await tester.pumpAndSettle();
    expect(find.text('-KES 25,000'), findsNothing);
    expect(find.text('≈ USD 193.50'), findsNothing);
    expect(find.text('≈ •••••'), findsWidgets);
  });

  testAppWidgets('says what moved after messages were read again', (
    tester,
  ) async {
    await DriftAppSettingsRepository(db).writeJson(
      MessageRecheck.noticeKey,
      RecheckNotice(
        count: 23,
        accountId: mpesaId,
        currency: 'KES',
        currencyChanged: true,
      ).toJson(),
    );
    await pump(tester, const ActivityScreen());
    expect(find.text('Amounts fixed from your messages'), findsOneWidget);
    expect(
      find.text(
        '23 amounts at M-Pesa were in KES. They are now in M-Pesa, counted '
        'in KES.',
      ),
      findsOneWidget,
    );
    // One action: See them shows that account and marks the note seen.
    expect(find.text('OK'), findsNothing);
    await tester.tap(find.byKey(const Key('recheck-see')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recheck-note')), findsNothing);
  });

  testAppWidgets('a payment typed in takes the account currency', (
    tester,
  ) async {
    await pump(tester, const Scaffold(body: AddTransactionSheet()));
    final field = find.widgetWithText(TextField, 'Amount');
    expect(tester.widget<TextField>(field).decoration!.prefixText, 'KES ');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1,200');
    await tester.pumpAndSettle();
    expect(find.text("≈ USD 9.29 at today's rate"), findsOneWidget);
  });

  testAppWidgets('the converter converts both ways', (tester) async {
    await pump(tester, const ConverterScreen());
    // USD to the account's KES by default.
    expect(find.byKey(const Key('converter-result')), findsOneWidget);
    expect(find.text('12,920.00'), findsOneWidget);
    expect(
      find.text('1 USD = 129.2 KES · 1 KES = 0.00774 USD'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Rates by ExchangeRate-API, updated today at'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('converter-swap')));
    await tester.pumpAndSettle();
    expect(find.text('0.77'), findsOneWidget);
  });
}
