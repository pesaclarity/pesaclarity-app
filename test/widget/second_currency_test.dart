import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

final _now = DateTime.utc(2026, 10, 27, 9);

void main() {
  setUp(() {
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  testAppWidgets(
    'a second currency from setup shows under the safe to spend figure '
    'at the day rate, comes first in the converter, and can be cleared in '
    'Profile',
    (tester) async {
      final db = openTestDatabase();
      await tester.runAsync(
        () => DriftAppSettingsRepository(db).writeJson(
          CurrencyController.ratesKey,
          ExchangeRates.fromJson({
            'base': 'USD',
            'rates': {'KES': 129.2, 'EUR': 0.92},
          }, fetchedAt: _now)!.toJson(),
        ),
      );
      final sms = FakeSmsSource(inbox: [mpesaSent(), mpesaTill()]);
      addTearDown(sms.close);
      await pumpApp(
        tester,
        db: db,
        sms: sms,
        overrides: [clockProvider.overrideWithValue(() => _now)],
      );

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('second-currency')),
          matching: find.text('None'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('second-currency')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('currency-search')), 'USD');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('currency-USD')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with KES'));
      await tester.pumpAndSettle();
      await pickSalaryIncome(tester);
      await tapText(tester, 'M-Pesa');
      await tapText(tester, 'Scan my messages');
      await tapText(tester, 'Allow access to messages');
      await tapText(tester, 'Continue');
      await tapText(tester, 'Go to Home');
      await openYourMonth(tester);

      // In Insights › Your month: safe to spend and On hand, each with its
      // dollars under it.
      final dollars = find.textContaining(RegExp(r'^≈ USD \d+\.\d\d$'));
      expect(find.byKey(const Key('hero-second-figure')), findsOneWidget);
      expect(dollars, findsNWidgets(2));
      // KES 3,685 on hand is USD 28.52 at 129.2.
      expect(find.text('≈ USD 28.52'), findsOneWidget);
      await backToHome(tester);

      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Base currency');
      expect(
        find.descendant(
          of: find.byKey(const Key('second-currency')),
          matching: find.text('USD'),
        ),
        findsOneWidget,
      );

      await tapText(tester, 'Currency converter');
      expect(
        find.descendant(
          of: find.byKey(const Key('converter-to')),
          matching: find.text('USD'),
        ),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapText(tester, 'Second currency');
      expect(find.widgetWithText(AppBar, 'Second currency'), findsOneWidget);
      await tester.tap(find.byKey(const Key('currency-none')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('second-currency')),
          matching: find.text('None'),
        ),
        findsOneWidget,
      );
      final saved = await tester.runAsync(
        () =>
            DriftAppSettingsRepository(db)
                .readJson(CurrencyController.settingsKey),
      );
      expect(saved!.containsKey('secondary'), isFalse);
    },
  );
}
