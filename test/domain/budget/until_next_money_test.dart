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
      nextMoney: CalendarDate(2026, 11, 24),
    );
    // 5,000 less a 500 buffer and 1,500 of bills, over 10 days.
    expect(r.days, 10);
    expect(r.dailyMinor, kes(300));
    expect(r.leftTodayMinor, kes(200));
    // (5,000 - 1,500) / 400 a day lasts 8 days.
    expect(r.lastsUntil, CalendarDate(2026, 11, 22));
  });

  test('irregular money plans a week at a time', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.rolling,
      onHandAtStartMinor: kes(7000),
      billsMinor: 0,
      spentTodayMinor: kes(1200),
      paceMinor: kes(800),
    );
    expect(r.days, rollingPlanDays);
    expect(r.dailyMinor, kes(900));
    expect(r.leftTodayMinor, 0);
    expect(r.overTodayMinor, kes(300));
    expect(r.nextMoney, isNull);
  });

  test('bills larger than the money leave nothing to spend', () {
    final r = UntilNextMoney.calculate(
      today: today,
      basis: NextMoneyBasis.noDate,
      onHandAtStartMinor: kes(1000),
      billsMinor: kes(2000),
      spentTodayMinor: 0,
      paceMinor: kes(100),
    );
    expect(r.dailyMinor, 0);
    expect(r.days, 1);
  });
}
