import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/budget/until_next_money.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

final today = CalendarDate(2026, 11, 14);

void main() {
  test('spreads what is on hand, less bills and a buffer, until the next '
      'money', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rhythm,
      onHandAtStartMinor: kes(5000),
      billsMinor: kes(1500),
      spentTodayMinor: kes(100),
      paceMinor: kes(400),
      usualTodayMinor: kes(400),
      historyDays: 28,
      nextMoney: CalendarDate(2026, 11, 24),
    );
    // 5,000 less a 500 buffer and 1,500 of bills, over 10 days.
    expect(r.days, 10);
    expect(r.dailyMinor, kes(300));
    expect(r.leftTodayMinor, kes(200));
    // (5,000 - 1,500) / 400 a day lasts 8 days.
    expect(r.lastsUntil, CalendarDate(2026, 11, 22));
  });

  test('irregular money plans a week at a time, at most a usual day', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rolling,
      onHandAtStartMinor: kes(7000),
      billsMinor: 0,
      spentTodayMinor: kes(1200),
      paceMinor: kes(800),
      usualTodayMinor: kes(800),
      historyDays: 28,
    );
    // 6,300 over 7 days would be 900; a usual day is 800.
    expect(r.days, rollingPlanDays);
    expect(r.dailyMinor, kes(800));
    expect(r.fromUsualDay, isTrue);
    expect(r.leftTodayMinor, 0);
    expect(r.overTodayMinor, kes(400));
    expect(r.nextMoney, isNull);
  });

  test('a lot on hand is not all safe to spend: the rest stays spare', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rolling,
      onHandAtStartMinor: kes(100000),
      billsMinor: kes(5000),
      spentTodayMinor: 0,
      paceMinor: kes(1400),
      usualTodayMinor: kes(1500),
      historyDays: 60,
    );
    expect(r.dailyMinor, kes(1500));
    expect(r.fromUsualDay, isTrue);
    // 100,000 − 5,000 of bills − a 10,000 buffer − 7 × 1,500.
    expect(r.spareMinor, kes(74500));
  });

  test('less than the usual day when the money is short', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rhythm,
      onHandAtStartMinor: kes(3000),
      billsMinor: 0,
      spentTodayMinor: 0,
      paceMinor: kes(800),
      usualTodayMinor: kes(800),
      historyDays: 60,
      nextMoney: today.addDays(9),
    );
    // 2,700 over 9 days.
    expect(r.dailyMinor, kes(300));
    expect(r.fromUsualDay, isFalse);
  });

  test('with too little history, spreads the money over a month', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rolling,
      onHandAtStartMinor: kes(30000),
      billsMinor: 0,
      spentTodayMinor: 0,
      paceMinor: kes(2000),
      usualTodayMinor: kes(2000),
      historyDays: 5,
    );
    // 27,000 after the buffer, over 30 days, not 7.
    expect(r.days, newPlanDays);
    expect(r.dailyMinor, kes(900));
    expect(r.fromUsualDay, isFalse);
  });

  test('bills larger than the money leave nothing to spend', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.noDate,
      onHandAtStartMinor: kes(1000),
      billsMinor: kes(2000),
      spentTodayMinor: 0,
      paceMinor: kes(100),
      usualTodayMinor: kes(100),
      historyDays: 28,
    );
    expect(r.dailyMinor, 0);
    expect(r.days, 1);
  });

  group('make it last', () {
    // 5,000 from support every 14 days; rent share due on the 20th.
    UntilNextMoney plan({int pace = 30000, int? pinned}) =>
        UntilNextMoney.calculate(
          today: today,
          basis: NextMoneyBasis.rhythm,
          onHandAtStartMinor: kes(5000),
          billsMinor: kes(1500),
          bills: [
            BillDue(
              name: 'Rent share',
              due: CalendarDate(2026, 11, 20),
              amountMinor: kes(1500),
            ),
          ],
          spentTodayMinor: 0,
          paceMinor: pace,
          usualTodayMinor: pace,
          historyDays: 60,
          nextMoney: today.addDays(14),
          pinnedDailyMinor: pinned,
        );

    test('bills, a buffer, then a daily amount to the last day', () {
      final r = plan();
      expect(r.bills.single.name, 'Rent share');
      expect(r.bufferMinor, kes(500));
      expect(r.dailyMinor, kes(3000) ~/ 14);
      expect(r.lastDay, today.addDays(13));
      expect(r.pinned, isFalse);
    });

    test('warns early when the usual pace uses it up first', () {
      // 3,500 after bills at 500 a day lasts 7 days of 14.
      final r = plan(pace: kes(500));
      expect(r.runsOutEarly, isTrue);
      expect(r.lastsUntil, today.addDays(7));
      expect(plan(pace: kes(100)).runsOutEarly, isFalse);
    });

    test('a chosen daily amount is kept, and what it leaves is spare', () {
      final r = plan(pinned: kes(150));
      expect(r.pinned, isTrue);
      expect(r.dailyMinor, kes(150));
      // 5,000 − 1,500 − 500 − 14 × 150.
      expect(r.spareMinor, kes(900));
    });
  });
}
