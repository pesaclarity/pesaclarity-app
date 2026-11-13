import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/periods.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  // A Friday.
  final today = CalendarDate(2026, 11, 13);

  AskPeriod p(String text) => parsePeriod(text, today)!;

  group('parsePeriod', () {
    test('today and yesterday, in English and Swahili', () {
      expect(p('how much today').from, today);
      expect(p('leo').from, today);
      expect(p('yesterday').from, CalendarDate(2026, 11, 12));
      expect(p('jana').to, today);
    });

    test('this and last week run Monday to Sunday', () {
      expect(p('this week').from, CalendarDate(2026, 11, 9));
      expect(p('this week').to, CalendarDate(2026, 11, 14));
      final last = p('last week');
      expect(last.from, CalendarDate(2026, 11, 2));
      expect(last.to, CalendarDate(2026, 11, 9));
    });

    test('this month so far and last month whole', () {
      expect(p('this month').from, CalendarDate(2026, 11, 1));
      expect(p('this month').to, CalendarDate(2026, 11, 14));
      expect(p('mwezi huu').kind, PeriodKind.month);
      final last = p('last month');
      expect(last.from, CalendarDate(2026, 10, 1));
      expect(last.to, CalendarDate(2026, 11, 1));
    });

    test('years', () {
      expect(p('this year').from, CalendarDate(2026, 1, 1));
      expect(p('last year').from, CalendarDate(2025, 1, 1));
      expect(p('last year').to, CalendarDate(2026, 1, 1));
      expect(p('in 2025').from, CalendarDate(2025, 1, 1));
      expect(parsePeriod('in 2030', today), isNull);
    });

    test('month names, with and without a year', () {
      expect(p('in october').from, CalendarDate(2026, 10, 1));
      expect(p('october 2025').from, CalendarDate(2025, 10, 1));
      // December not yet come this year: last December.
      expect(p('in december').from, CalendarDate(2025, 12, 1));
      expect(p('sept').from.month, 9);
      // "may" alone is a word, not a month.
      expect(parsePeriod('may I ask', today), isNull);
      expect(p('in may').from, CalendarDate(2026, 5, 1));
    });

    test('since a month, and the last few months or days', () {
      final since = p('since june');
      expect(since.from, CalendarDate(2026, 6, 1));
      expect(since.to, CalendarDate(2026, 11, 14));
      final three = p('last 3 months');
      expect(three.from, CalendarDate(2026, 9, 1));
      expect(three.length, 3);
      expect(p('past six months').from, CalendarDate(2026, 6, 1));
      expect(p('last 7 days').from, CalendarDate(2026, 11, 7));
    });

    test('nothing named', () {
      expect(parsePeriod('how much did I spend on food', today), isNull);
    });

    test('finds where the words are', () {
      final m = findPeriod('Food last month please', today)!;
      expect(m.text, 'last month');
      expect(m.start, 5);
    });
  });

  group('previous', () {
    test('a month so far compares with the whole month before', () {
      final prev = AskPeriod.thisMonth(today).previous();
      expect(prev.from, CalendarDate(2026, 10, 1));
      expect(prev.to, CalendarDate(2026, 11, 1));
    });

    test('a week, a year, a day and N months', () {
      expect(
        AskPeriod.thisWeek(today).previous().from,
        CalendarDate(2026, 11, 2),
      );
      expect(AskPeriod.thisYear(today).previous().from.year, 2025);
      expect(
        AskPeriod.today(today).previous().from,
        CalendarDate(2026, 11, 12),
      );
      final three = AskPeriod.lastMonths(3, today).previous();
      expect(three.from, CalendarDate(2026, 6, 1));
      expect(three.to, CalendarDate(2026, 9, 1));
    });
  });

  group('labels', () {
    test('headings', () {
      expect(p('last month').label(today), 'October 2026');
      expect(p('this year').label(today), 'Jan to Nov 2026');
      expect(p('this week').label(today), 'Mon 9 to Fri 13 Nov');
      expect(p('today').label(today), 'Today');
    });

    test('phrases', () {
      expect(p('last month').phrase(today), 'last month');
      expect(p('in september').phrase(today), 'in September');
      expect(p('this year').phrase(today), 'this year');
      expect(p('october 2025').phrase(today), 'in October 2025');
    });

    test('JSON round trip', () {
      final period = p('last 3 months');
      expect(AskPeriod.fromJson(period.toJson()), period);
    });
  });
}
