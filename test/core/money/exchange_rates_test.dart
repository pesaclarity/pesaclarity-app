import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';

void main() {
  final at = DateTime.utc(2026, 10, 27, 6);

  test('reads either common rates shape', () {
    final a = ExchangeRates.fromJson({
      'result': 'success',
      'base_code': 'USD',
      'rates': {'USD': 1, 'KES': 129.2, 'EUR': 0.92},
    }, fetchedAt: at)!;
    expect(a.base, 'USD');
    expect(a.rates['KES'], 129.2);
    final b = ExchangeRates.fromJson({
      'base': 'eur',
      'conversion_rates': {'usd': 1.087},
    }, fetchedAt: at)!;
    expect(b.base, 'EUR');
    expect(b.rates, {'USD': 1.087, 'EUR': 1});
  });

  test('refuses anything else', () {
    expect(ExchangeRates.fromJson('nope', fetchedAt: at), isNull);
    expect(ExchangeRates.fromJson({'base': 'USD'}, fetchedAt: at), isNull);
    expect(
      ExchangeRates.fromJson({
        'base': 'USD',
        'rates': {'KES': -1, 'X': 'a'},
      }, fetchedAt: at),
      isNull,
    );
  });

  test('saves and reads back', () {
    final rates = ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': 129.2},
    }, fetchedAt: at)!;
    final back = ExchangeRates.fromSaved(rates.toJson())!;
    expect(back.base, 'USD');
    expect(back.rates['KES'], 129.2);
    expect(back.fetchedAt, at);
  });

  group('converter', () {
    final rates = ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': 129.2, 'UGX': 3700, 'BHD': 0.376},
    }, fetchedAt: at)!;

    test('converts into the base through any rates base', () {
      final kes = CurrencyConverter(base: 'KES', rates: rates);
      // USD 6.99 is KES 903.11.
      expect(kes.toBase(699, 'USD'), 90311);
      // UGX has no minor digits: UGX 3,700 is KES 129.20.
      expect(kes.toBase(3700, 'UGX'), 12920);
      // BHD has three: BHD 0.376 is KES 129.20.
      expect(kes.toBase(376, 'BHD'), 12920);
      expect(kes.fromBase(12920, 'USD'), 100);
      expect(kes.toBase(500, 'KES'), 500);
    });

    test('own rates win, and unknown currencies have no rate', () {
      final kes = CurrencyConverter(
        base: 'KES',
        rates: rates,
        ownRates: {'USD': 0.01},
      );
      expect(kes.toBase(100, 'USD'), 10000);
      expect(kes.toBase(100, 'XYZ'), isNull);
      expect(const CurrencyConverter(base: 'KES').toBase(100, 'USD'), isNull);
    });
  });

  test('suggests the currency of the phone region', () {
    expect(currencyOfRegion('KE'), 'KES');
    expect(currencyOfRegion('ng'), 'NGN');
    expect(currencyOfRegion('DE'), 'EUR');
    expect(currencyOfRegion(null), isNull);
    expect(suggestedCurrency('ZZ'), BaseCurrency.code);
  });

  test('knows minor digits from the catalogue', () {
    expect(minorUnitDigits('KES'), 2);
    expect(minorUnitDigits('UGX'), 0);
    expect(minorUnitDigits('BHD'), 3);
    expect(rescaleMinor(12345, fromDigits: 2, toDigits: 0), 123);
    expect(rescaleMinor(-150, fromDigits: 2, toDigits: 0), -2);
    expect(rescaleMinor(12, fromDigits: 0, toDigits: 3), 12000);
  });

  test('Money takes the base currency when none is given', () {
    addTearDown(() => BaseCurrency.code = 'KES');
    BaseCurrency.code = 'USD';
    expect(Money(100).currency, 'USD');
    expect(Money(100, currency: 'KES').currency, 'KES');
  });
}
