import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final today = CalendarDate(2026, 11, 20);
  const categories = <int, SummaryCategory>{
    1: (key: 'sales', name: 'Sales', type: CategoryType.income),
    2: (key: 'stock', name: 'Stock and supplies', type: CategoryType.expense),
    3: (key: 'wages', name: 'Wages', type: CategoryType.expense),
    4: (key: 'owner_pay', name: 'Paid yourself', type: CategoryType.transfer),
    5: (key: 'contributions', name: 'Contributions', type: CategoryType.income),
    6: (
      key: 'member_loans',
      name: 'Loans to members',
      type: CategoryType.expense,
    ),
  };

  final business = [
    inflow(
      at: eat(2026, 11, 3),
      amount: kes(15000),
      payeeId: 1,
      categoryId: 1,
      categoryType: CategoryType.income,
    ),
    inflow(
      at: eat(2026, 11, 10),
      amount: kes(9500),
      payeeId: 2,
      categoryId: 1,
      categoryType: CategoryType.income,
    ),
    entry(
      at: eat(2026, 11, 4),
      amount: kes(11000),
      categoryId: 2,
      categoryType: CategoryType.expense,
    ),
    entry(
      at: eat(2026, 11, 15),
      amount: kes(3000),
      categoryId: 3,
      categoryType: CategoryType.expense,
      fee: kes(30),
    ),
    entry(
      at: eat(2026, 11, 16),
      amount: kes(6000),
      categoryId: 4,
      categoryType: CategoryType.transfer,
    ),
    // Last month: not counted.
    inflow(
      at: eat(2026, 10, 28),
      amount: kes(50000),
      payeeId: 1,
      categoryId: 1,
      categoryType: CategoryType.income,
    ),
  ];

  test('a business shows profit, its largest categories and pay', () {
    final s = SpaceSummary.of(
      SpaceKind.business,
      business,
      today: today,
      categories: categories,
      balanceMinor: kes(4000),
    );
    expect(s.headline, 'Profit this month');
    expect(s.inMinor, kes(24500));
    // Stock, wages and the fee; paying yourself is not a cost.
    expect(s.outMinor, kes(14030));
    expect(s.figureMinor, kes(10470));
    expect(s.paidYourselfMinor, kes(6000));
    expect(s.rows.map((r) => r.name), ['Sales', 'Stock and supplies', 'Wages']);
    expect(s.rows.first.isIncome, isTrue);
  });

  test('a farm counts the season', () {
    final s = SpaceSummary.of(
      SpaceKind.farm,
      business,
      today: today,
      categories: categories,
      balanceMinor: 0,
    );
    expect(s.headline, 'Profit this season');
    expect(s.from, CalendarDate(2026, 6, 1));
    expect(s.inMinor, kes(74500));
  });

  test('a savings group shows its pot and who paid in', () {
    final s = SpaceSummary.of(
      SpaceKind.savingsGroup,
      [
        for (final p in [1, 2, 3])
          inflow(
            at: eat(2026, 11, 5),
            amount: kes(1000),
            payeeId: p,
            categoryId: 5,
            categoryType: CategoryType.income,
          ),
        inflow(
          at: eat(2026, 11, 6),
          amount: kes(1000),
          payeeId: 1,
          categoryId: 5,
          categoryType: CategoryType.income,
        ),
        entry(
          at: eat(2026, 11, 8),
          amount: kes(2000),
          categoryId: 6,
          categoryType: CategoryType.expense,
        ),
      ],
      today: today,
      categories: categories,
      balanceMinor: kes(86000),
    );
    expect(s.headline, "In the group's pot");
    expect(s.figureMinor, kes(86000));
    expect(s.payersCount, 3);
    expect(s.loansOutCount, 1);
  });
}
