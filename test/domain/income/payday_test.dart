import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/home/home_period.dart';
import 'package:pesaclarity/src/domain/income/payday.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

List<LedgerEntry> _salary(
  List<(int, int)> monthDays, {
  int payee = 1,
  int shillings = 110000,
  int idFrom = 100,
}) => [
  for (final (i, (m, d)) in monthDays.indexed)
    inflow(
      id: idFrom + i,
      at: eat(2026, m, d, 7),
      amount: kes(shillings),
      payeeId: payee,
      categoryType: CategoryType.income,
    ),
];

void main() {
  test('payday inside the current month', () {
    final today = CalendarDate(2026, 11, 19);
    final p = Payday.of(
      _salary([(8, 5), (9, 5), (10, 5), (11, 5)]),
      today: today,
    );
    expect(p!.last, CalendarDate(2026, 11, 5));
    expect(p.nextAfter(today), p.last.addDays(p.gapDays));
    expect(p.nextAfter(CalendarDate(2026, 12, 20)), CalendarDate(2026, 12, 21));
  });

  test('payday in the previous month', () {
    final today = CalendarDate(2026, 11, 19);
    final p = Payday.of(
      _salary([(7, 31), (8, 31), (9, 30), (10, 31)]),
      today: today,
    );
    expect(p!.last, CalendarDate(2026, 10, 31));
  });

  test('no regular income: no payday', () {
    final today = CalendarDate(2026, 11, 19);
    final odd = [
      for (final (i, (m, d)) in [(9, 2), (9, 4), (10, 20), (11, 18)].indexed)
        inflow(
          id: i + 1,
          at: eat(2026, m, d),
          amount: kes(800),
          payeeId: 7,
          categoryType: CategoryType.income,
        ),
    ];
    expect(Payday.of(odd, today: today), isNull);
    expect(Payday.of(const [], today: today), isNull);
  });

  test('a payday long missed is no longer one', () {
    final today = CalendarDate(2026, 11, 19);
    expect(
      Payday.of(_salary([(6, 25), (7, 25), (8, 25), (9, 25)]), today: today),
      isNull,
    );
  });

  test('several sources: the largest regular one sets payday', () {
    final today = CalendarDate(2026, 11, 19);
    final support = [
      for (final (i, (m, d)) in [(10, 3), (10, 17), (10, 31), (11, 14)].indexed)
        inflow(
          id: 200 + i,
          at: eat(2026, m, d),
          amount: kes(3000),
          payeeId: 2,
          categoryType: CategoryType.income,
        ),
    ];
    final p = Payday.of([
      ..._salary([(8, 25), (9, 25), (10, 25)]),
      ...support,
    ], today: today);
    expect(p!.last, CalendarDate(2026, 10, 25));
    expect(p.gapDays, inInclusiveRange(30, 31));
  });

  test('the period runs from payday, its money in included, to today', () {
    final today = CalendarDate(2026, 11, 19);
    final history = [
      ..._salary([(8, 31), (9, 30), (10, 31)]),
      // The evening before payday is outside.
      entry(
        id: 1,
        at: eat(2026, 10, 30, 22),
        amount: kes(500),
        categoryType: CategoryType.expense,
      ),
      entry(
        id: 2,
        at: eat(2026, 11, 19, 23),
        amount: kes(200),
        categoryType: CategoryType.expense,
      ),
    ];
    final payday = Payday.of(history, today: today)!.last;
    final view = HomePeriodView.of(
      history,
      period: HomePeriod.thisMonth,
      today: today,
      payday: payday,
    );
    expect(view.sincePayday, isTrue);
    expect(view.span, DateSpan(CalendarDate(2026, 10, 31), today));
    expect(view.sums.inMinor, kes(110000));
    expect(view.sums.outMinor, kes(200));

    final month = HomePeriodView.of(
      history,
      period: HomePeriod.thisMonth,
      today: today,
    );
    expect(month.sincePayday, isFalse);
    expect(month.span.first, CalendarDate(2026, 11, 1));
    expect(month.sums.inMinor, 0);
  });
}
