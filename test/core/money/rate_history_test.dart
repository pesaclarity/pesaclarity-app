import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

ExchangeRates _usd(double kes, {required DateTime at}) =>
    ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': kes, 'EUR': 0.92},
    }, fetchedAt: at)!;

void main() {
  final nov2 = DayRates(
    CalendarDate(2026, 11, 2),
    _usd(130, at: DateTime.utc(2026, 11, 2, 6)),
  );
  final nov4 = DayRates(
    CalendarDate(2026, 11, 4),
    _usd(128, at: DateTime.utc(2026, 11, 4, 6)),
  );
  final history = RateHistory([nov4, nov2]);

  group('RateHistory.on', () {
    test("a day's own rates", () {
      expect(history.on(CalendarDate(2026, 11, 4)), same(nov4));
    });

    test('else the closest earlier day', () {
      expect(history.on(CalendarDate(2026, 11, 3)), same(nov2));
      expect(history.on(CalendarDate(2026, 11, 30)), same(nov4));
    });

    test('before the first day, the oldest kept', () {
      expect(history.on(CalendarDate(2026, 10, 1)), same(nov2));
    });

    test('none kept', () {
      expect(RateHistory.empty.on(CalendarDate(2026, 11, 3)), isNull);
    });
  });

  group('converting at the rates of the day', () {
    // Base USD: a KES payment converts at its day's KES rate.
    final converter = CurrencyConverter(
      base: 'USD',
      rates: _usd(129.2, at: DateTime.utc(2026, 11, 10, 6)),
      history: history,
    );

    test('same day, earlier day and approximate', () {
      final sameDay = converter.convert(
        1300000,
        'KES',
        DateTime.utc(2026, 11, 2, 9),
      )!;
      expect((sameDay.baseMinor, sameDay.kind), (10000, RateKind.sameDay));
      expect(sameDay.day, CalendarDate(2026, 11, 2));

      final earlier = converter.convert(
        1300000,
        'KES',
        DateTime.utc(2026, 11, 3, 9),
      )!;
      expect((earlier.baseMinor, earlier.kind), (10000, RateKind.earlierDay));

      final approximate = converter.convert(
        1300000,
        'KES',
        DateTime.utc(2026, 10, 1, 9),
      )!;
      expect(approximate.kind, RateKind.approximate);
      expect(approximate.day, CalendarDate(2026, 11, 2));
    });

    test("later rates don't change an earlier day's amount", () {
      final a = converter.convert(2560000, 'KES', DateTime.utc(2026, 11, 4, 9));
      expect(a!.baseMinor, 20000);
      // USD 200 at 128 even though today's rate is 129.2.
    });

    test('the latest rates when none are kept by day', () {
      final plain = CurrencyConverter(
        base: 'USD',
        rates: _usd(129.2, at: DateTime.utc(2026, 11, 10, 6)),
      );
      final c = plain.convert(1292000, 'KES', DateTime.utc(2026, 1, 2))!;
      expect((c.baseMinor, c.kind), (10000, RateKind.latest));
    });

    test('own rates win over the day', () {
      final own = CurrencyConverter(
        base: 'USD',
        history: history,
        ownRates: const {'KES': 100},
      );
      final c = own.convert(1000000, 'KES', DateTime.utc(2026, 11, 2, 9))!;
      expect((c.baseMinor, c.kind), (10000, RateKind.own));
    });

    test('the rate the person got, in the base', () {
      // KES 25,800 for USD 200: one USD bought 129 KES.
      final got = converter.convert(
        2580000,
        'KES',
        DateTime.utc(2026, 11, 2, 9),
        gotCurrency: 'USD',
        gotRate: 129,
      )!;
      expect(
        (got.baseMinor, got.kind, got.baseBuys),
        (20000, RateKind.got, 129),
      );
    });

    test('the rate the person got, through another currency', () {
      // Base EUR; one USD bought 129 KES; the day's USD is 1 / 0.92 EUR.
      final eur = CurrencyConverter(base: 'EUR', history: history);
      final got = eur.convert(
        2580000,
        'KES',
        DateTime.utc(2026, 11, 2, 9),
        gotCurrency: 'USD',
        gotRate: 129,
      )!;
      expect(got.baseMinor, 18400);
      expect(got.kind, RateKind.got);
    });

    test('minor digits of each currency', () {
      // UGX has none; BHD has three.
      expect(convertMinor(100, from: 'USD', to: 'UGX', rate: 3700), 3700);
      expect(convertMinor(100, from: 'USD', to: 'BHD', rate: 0.376), 376);
    });
  });
}
