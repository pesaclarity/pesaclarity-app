import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/money/money_format.dart';

void main() {
  group('formatMoney', () {
    test('formats whole shillings without decimals', () {
      expect(formatMoney(Money(120000)), 'KES 1,200');
      expect(formatMoney(Money.major(1200)), 'KES 1,200');
    });

    test('shows cents only when there are some', () {
      expect(formatMoney(Money(120050)), 'KES 1,200.50');
      expect(formatMoney(Money(5)), 'KES 0.05');
    });

    test('can always show cents', () {
      expect(
        formatMoney(Money(120000), alwaysShowMinorUnits: true),
        'KES 1,200.00',
      );
    });

    test('groups thousands', () {
      expect(formatMoney(Money(0)), 'KES 0');
      expect(formatMoney(Money(99900)), 'KES 999');
      expect(formatMoney(Money(100000)), 'KES 1,000');
      expect(formatMoney(Money(1234567890)), 'KES 12,345,678.90');
    });

    test('puts the sign before the currency', () {
      expect(formatMoney(Money(-120000)), '-KES 1,200');
    });

    test('can leave out the currency', () {
      expect(formatMoney(Money(120000), withCurrency: false), '1,200');
    });

    test('respects currencies without minor units', () {
      expect(formatMoney(Money(50000, currency: 'UGX')), 'UGX 50,000');
      expect(Money.major(50000, currency: 'UGX').minorUnits, 50000);
    });
  });

  group('Money', () {
    test('adds and subtracts in minor units', () {
      expect(Money(150) + Money(250), Money(400));
      expect(Money(150) - Money(250), Money(-100));
    });

    test('refuses to mix currencies', () {
      expect(() => Money(1) + Money(1, currency: 'USD'), throwsArgumentError);
    });
  });
}
