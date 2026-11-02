import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/findings.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const food = 7;
const transport = 8;

/// Monday 26 October 2026.
final today = CalendarDate(2026, 10, 26);

void main() {
  final history = [
    // October so far.
    entry(at: eat(2026, 10, 3), amount: kes(9000), categoryId: food),
    entry(at: eat(2026, 10, 4), amount: kes(1000), categoryId: transport),
    entry(
      at: eat(2026, 10, 5),
      amount: kes(200),
      fee: kes(30),
      categoryId: food,
    ),
    inflow(
      at: eat(2026, 10, 1),
      amount: kes(40000),
      categoryType: CategoryType.income,
    ),
    // The same days of September.
    entry(at: eat(2026, 9, 3), amount: kes(6000), categoryId: food),
    entry(at: eat(2026, 9, 4), amount: kes(1500), categoryId: transport),
    entry(
      at: eat(2026, 9, 5),
      amount: kes(100),
      fee: kes(10),
      categoryId: food,
    ),
    inflow(
      at: eat(2026, 9, 1),
      amount: kes(45000),
      categoryType: CategoryType.income,
    ),
    // After the 26th of September: outside the comparison.
    entry(at: eat(2026, 9, 28), amount: kes(50000), categoryId: food),
  ];

  test('finds the category that moved most, fees and money in', () {
    final findings = findingsFor(history, today: today);
    expect(findings, hasLength(3));

    final category = findings[0] as CategoryFinding;
    expect(category.slice, const CategorySlice(food));
    expect(category.nowMinor, kes(9200));
    expect(category.changeMinor, kes(3100));

    final fees = findings[1] as FeesFinding;
    expect(fees.nowMinor, kes(30));
    expect(fees.changeMinor, kes(20));

    final income = findings[2] as IncomeFinding;
    expect(income.nowMinor, kes(40000));
    expect(income.changeMinor, kes(-5000));
  });

  test('each finding opens the month so far, narrowed to its money', () {
    final [category, fees, income] = findingsFor(history, today: today);
    final month = (CalendarDate(2026, 10, 1), today);

    final c = category.filterFor(today);
    expect((c.from, c.to), month);
    expect(c.categoryId, food);

    expect(fees.filterFor(today).type, ActivityType.fees);
    expect(income.filterFor(today).type, ActivityType.moneyIn);
  });

  test('small category changes are not findings', () {
    final quiet = [
      entry(at: eat(2026, 10, 3), amount: kes(400), categoryId: food),
      entry(at: eat(2026, 9, 3), amount: kes(100), categoryId: food),
    ];
    expect(findingsFor(quiet, today: today), isEmpty);
  });
}
