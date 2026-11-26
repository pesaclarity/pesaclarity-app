import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/home/home_period.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  /// Sunday 22 November 2026.
  final today = CalendarDate(2026, 11, 22);

  group('spans', () {
    test('weeks from Monday, months to today', () {
      expect(
        HomePeriod.thisWeek.spanOn(today),
        DateSpan(CalendarDate(2026, 11, 16), today),
      );
      expect(
        HomePeriod.lastWeek.spanOn(today),
        DateSpan(CalendarDate(2026, 11, 9), CalendarDate(2026, 11, 15)),
      );
      expect(
        HomePeriod.thisMonth.spanOn(today),
        DateSpan(CalendarDate(2026, 11, 1), today),
      );
      expect(
        HomePeriod.lastMonth.spanOn(today),
        DateSpan(CalendarDate(2026, 10, 1), CalendarDate(2026, 10, 31)),
      );
    });

    test('a week from Sunday', () {
      expect(
        HomePeriod.thisWeek.spanOn(today, weekStartsOn: DateTime.sunday),
        DateSpan(today, today),
      );
      expect(
        HomePeriod.lastWeek.spanOn(today, weekStartsOn: DateTime.sunday),
        DateSpan(CalendarDate(2026, 11, 15), CalendarDate(2026, 11, 21)),
      );
    });
  });

  group('the view', () {
    final history = [
      inflow(
        id: 1,
        at: eat(2026, 11, 21, 18, 40),
        amount: kes(6500),
        categoryType: CategoryType.income,
      ),
      entry(
        id: 2,
        at: eat(2026, 11, 22, 14, 12),
        amount: kes(1340),
        fee: kes(7),
        categoryType: CategoryType.expense,
      ),
      // A move to savings of the person's own: in no total.
      entry(
        id: 3,
        at: eat(2026, 11, 21, 8),
        amount: kes(3000),
        transferPairId: 4,
      ),
      entry(
        id: 4,
        at: eat(2026, 11, 21, 8, 1),
        amount: kes(3000),
        accountId: 2,
        direction: TransactionDirection.inflow,
        transferPairId: 3,
      ),
      entry(
        id: 5,
        at: eat(2026, 11, 20, 13, 20),
        amount: kes(620),
        categoryType: CategoryType.expense,
      ),
      entry(
        id: 6,
        at: eat(2026, 11, 19, 9),
        amount: kes(100),
        categoryType: CategoryType.expense,
      ),
      // Last week.
      entry(
        id: 7,
        at: eat(2026, 11, 12, 9),
        amount: kes(900),
        categoryType: CategoryType.expense,
      ),
    ];
    final view = HomePeriodView.of(
      history,
      period: HomePeriod.thisWeek,
      today: today,
    );

    test('money in and out leave own transfers out; fees are in out', () {
      expect(view.sums.inMinor, kes(6500));
      expect(view.sums.outMinor, kes(1340 + 7 + 620 + 100));
      expect(view.sums.feesMinor, kes(7));
      expect(view.sums.differenceMinor, kes(6500 - 2067));
    });

    test('the last three days, newest first, each with its sums', () {
      expect(view.days.map((d) => d.date), [
        today,
        CalendarDate(2026, 11, 21),
        CalendarDate(2026, 11, 20),
      ]);
      final saturday = view.days[1];
      expect(saturday.sums.inMinor, kes(6500));
      expect(saturday.sums.outMinor, 0);
      expect(saturday.lines.whereType<OwnTransferLine>(), hasLength(1));
      expect(saturday.lines, hasLength(2));
    });

    test('last week is whole and apart', () {
      final last = HomePeriodView.of(
        history,
        period: HomePeriod.lastWeek,
        today: today,
      );
      expect(last.sums.outMinor, kes(900));
      expect(last.days, hasLength(1));
      expect(last.hasRecords, isTrue);
    });

    test('no records at all', () {
      final empty = HomePeriodView.of(
        const [],
        period: HomePeriod.thisWeek,
        today: today,
      );
      expect(empty.hasRecords, isFalse);
      expect(empty.sums.inMinor, 0);
    });
  });
}
