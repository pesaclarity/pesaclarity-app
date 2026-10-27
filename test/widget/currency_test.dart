import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';
import 'package:pesaclarity/src/features/currency/presentation/base_currency_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

class _Rates implements RatesClient {
  @override
  Future<ExchangeRates?> fetch(String base) async => ExchangeRates.fromJson({
    'base': 'USD',
    'rates': {'KES': 129.2, 'EUR': 0.92},
  }, fetchedAt: DateTime.utc(2026, 10, 27, 6));
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  testAppWidgets('setup suggests the region currency, and another can be '
      'picked', (tester) async {
    await pumpApp(tester, db: db, region: 'DE');
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Which currency do you count in?'), findsOneWidget);
    expect(find.text("FROM YOUR PHONE'S REGION"), findsOneWidget);
    expect(find.text('Continue with EUR'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('currency-search')),
      'shilling',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kenyan Shilling'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with KES'));
    await tester.pumpAndSettle();

    expect(find.text('Which accounts do you use?'), findsOneWidget);
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(CurrencyController.settingsKey),
    );
    expect(saved, containsPair('base', 'KES'));
    expect(saved, containsPair('chosen', true));
  });

  testAppWidgets('switching asks first and says what moves', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ratesClientProvider.overrideWithValue(_Rates()),
          ratesConfiguredProvider.overrideWithValue(true),
          deviceRegionProvider.overrideWithValue('KE'),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 27, 9)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BaseCurrencyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rates load once you are online'), findsOneWidget);

    await tester.tap(find.text('Refresh rates'));
    await tester.pumpAndSettle();
    expect(find.text('Rates updated today'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('currency-search')), 'USD');
    await tester.pumpAndSettle();
    expect(find.text('1 KES = 0.00774 USD'), findsOneWidget);

    await tester.tap(find.text('US Dollar'));
    await tester.pumpAndSettle();
    expect(find.text('Count in USD?'), findsOneWidget);
    await tester.tap(find.text('Keep KES'));
    await tester.pumpAndSettle();
    expect(BaseCurrency.code, 'KES');

    await tester.tap(find.text('US Dollar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to USD'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Totals show in USD. Each transaction keeps the '
        'currency it was paid in.',
      ),
      findsOneWidget,
    );
  });
}
