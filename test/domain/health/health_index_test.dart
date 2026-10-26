import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

final october = YearMonth(2026, 10);

/// Inputs that earn full marks on every indicator.
HealthInputs perfect({
  int income = 100000,
  int spending = 50000,
  int billsDue = 3,
  int billsPaidOnTime = 3,
  int essentials = 40000,
  int savingsBalance = 120000,
  int saved = 20000,
  int debtPayments = 10000,
  int overdraftDays = 0,
  int leakage = 5000,
  int plannedCategories = 4,
  int categoriesWithinBudget = 4,
}) => HealthInputs(
  month: october,
  incomeMinor: kes(income),
  spendingMinor: kes(spending),
  billsDue: billsDue,
  billsPaidOnTime: billsPaidOnTime,
  essentialsMinor: kes(essentials),
  savingsBalanceMinor: kes(savingsBalance),
  savedMinor: kes(saved),
  debtPaymentsMinor: kes(debtPayments),
  overdraftDays: overdraftDays,
  leakageMinor: kes(leakage),
  plannedCategories: plannedCategories,
  categoriesWithinBudget: categoriesWithinBudget,
);

int points(HealthIndex index, HealthIndicator indicator) =>
    index.pointsOf(indicator);

void main() {
  group('HealthBand', () {
    test('follows the spec\'s band edges', () {
      expect(HealthBand.of(0), HealthBand.struggling);
      expect(HealthBand.of(39), HealthBand.struggling);
      expect(HealthBand.of(40), HealthBand.coping);
      expect(HealthBand.of(69), HealthBand.coping);
      expect(HealthBand.of(70), HealthBand.healthy);
      expect(HealthBand.of(100), HealthBand.healthy);
    });
  });

  group('HealthIndex.compute', () {
    test('full marks everywhere is 100, with nothing left to do', () {
      final index = HealthIndex.compute(perfect());
      expect(index.score, 100);
      expect(index.band, HealthBand.healthy);
      expect(index.indicators.every((s) => s.isFull), isTrue);
      expect(index.bestAction, isNull);
    });

    test('each indicator is worth 12.5 points', () {
      final index = HealthIndex.compute(perfect(overdraftDays: 99));
      expect(points(index, HealthIndicator.overdraftReliance), 0);
      expect(index.score, 88); // 87.5 rounds up.
    });

    test('scores halfway between its thresholds as half marks', () {
      final index = HealthIndex.compute(
        perfect(
          spending: 105000,
          billsDue: 2,
          billsPaidOnTime: 1,
          savingsBalance: 60000,
          saved: 10000,
          debtPayments: 35000,
          overdraftDays: 4,
          leakage: 20000,
          plannedCategories: 2,
          categoriesWithinBudget: 1,
        ),
      );
      for (final indicator in HealthIndicator.values) {
        expect(points(index, indicator), 625, reason: indicator.label);
      }
      expect(index.score, 50);
      expect(index.band, HealthBand.coping);
    });

    test('thresholds are inclusive at full marks and at zero', () {
      final atFull = HealthIndex.compute(
        perfect(spending: 90000, debtPayments: 20000, leakage: 10000),
      );
      expect(atFull.score, 100);

      final atZero = HealthIndex.compute(
        perfect(spending: 120000, debtPayments: 50000, leakage: 30000),
      );
      expect(points(atZero, HealthIndicator.spendingVsIncome), 0);
      expect(points(atZero, HealthIndicator.debtLoad), 0);
      expect(points(atZero, HealthIndicator.leakageShare), 0);
    });

    test('an empty month scores what there is nothing to fail', () {
      final index = HealthIndex.compute(HealthInputs(month: october));
      expect(points(index, HealthIndicator.spendingVsIncome), 1250);
      expect(points(index, HealthIndicator.billsOnTime), 1250);
      expect(points(index, HealthIndicator.emergencyCushion), 0);
      expect(points(index, HealthIndicator.savingsRate), 0);
      expect(points(index, HealthIndicator.debtLoad), 1250);
      expect(points(index, HealthIndicator.overdraftReliance), 1250);
      expect(points(index, HealthIndicator.leakageShare), 1250);
      expect(points(index, HealthIndicator.planAdherence), 0);
      expect(index.score, 63); // 62.5 rounds up.
      expect(index.weakestPillar, HealthPillar.save);

      final action = index.bestAction!;
      expect(action.indicator, HealthIndicator.emergencyCushion);
      expect(action.gainPoints, 12);
      expect(
        action.message,
        'Build your savings to cover 3 months of essentials.',
      );
    });

    test('with no income, any spending or debt earns nothing', () {
      final index = HealthIndex.compute(
        HealthInputs(
          month: october,
          spendingMinor: kes(100),
          debtPaymentsMinor: kes(100),
          leakageMinor: kes(100),
          savedMinor: kes(100),
        ),
      );
      expect(points(index, HealthIndicator.spendingVsIncome), 0);
      expect(points(index, HealthIndicator.debtLoad), 0);
      expect(points(index, HealthIndicator.leakageShare), 0);
      expect(points(index, HealthIndicator.savingsRate), 1250);
      expect(index.band, HealthBand.struggling);
    });

    test('savings with no essentials to cover is a full cushion', () {
      final index = HealthIndex.compute(
        HealthInputs(month: october, savingsBalanceMinor: kes(10)),
      );
      expect(points(index, HealthIndicator.emergencyCushion), 1250);
    });

    test('a negative savings balance is no cushion', () {
      final index = HealthIndex.compute(perfect(savingsBalance: -5000));
      expect(points(index, HealthIndicator.emergencyCushion), 0);
    });

    test('the weakest pillar goes to the earlier one on a tie', () {
      final index = HealthIndex.compute(
        perfect(billsPaidOnTime: 0, overdraftDays: 99),
      );
      expect(
        index.pillarCentipoints(HealthPillar.spend),
        index.pillarCentipoints(HealthPillar.borrow),
      );
      expect(index.weakestPillar, HealthPillar.spend);
    });

    test('the change since last month is the score difference', () {
      final last = HealthIndex.compute(perfect(overdraftDays: 99));
      final now = HealthIndex.compute(perfect());
      expect(now.changeSince(last), 12);
      expect(now.changeSince(null), isNull);
    });
  });

  group('HealthIndex.bestAction', () {
    HealthAction actionFor(HealthInputs inputs) =>
        HealthIndex.compute(inputs).bestAction!;

    test('picks the indicator with the largest gap and says how much', () {
      final action = actionFor(perfect(saved: 5000, overdraftDays: 1));
      expect(action.indicator, HealthIndicator.savingsRate);
      expect(action.amountMinor, kes(15000));
      expect(action.gainPoints, 9);
      expect(
        action.message,
        'Save KES 15,000 more a month to reach 20% of income.',
      );
    });

    test('names an amount for each money indicator', () {
      expect(
        actionFor(perfect(spending: 110000)).message,
        'Spend KES 20,000 less a month to keep spending under 90% of income.',
      );
      expect(
        actionFor(perfect(savingsBalance: 20000)).message,
        'Build your savings by KES 100,000 to cover 3 months of essentials.',
      );
      expect(
        actionFor(perfect(debtPayments: 40000)).message,
        'Bring debt payments down by KES 20,000 a month, to under 20% of '
        'income.',
      );
      expect(
        actionFor(perfect(leakage: 25000)).message,
        'Cut leakages by KES 15,000 a month, to under 10% of income.',
      );
    });

    test('counts bills, days and categories', () {
      expect(
        actionFor(perfect(billsPaidOnTime: 1)).message,
        'Pay your 2 late bills by their due dates.',
      );
      expect(
        actionFor(perfect(billsPaidOnTime: 2)).message,
        'Pay your one late bill by its due date.',
      );
      expect(
        actionFor(perfect(overdraftDays: 3)).message,
        'Go a month without Fuliza. You used it on 3 days.',
      );
      expect(
        actionFor(perfect(categoriesWithinBudget: 2)).message,
        'Keep your 2 over-budget categories within their plans.',
      );
      expect(
        actionFor(perfect(plannedCategories: 0, categoriesWithinBudget: 0))
            .message,
        'Set a budget for your spending categories in Plan.',
      );
    });

    test('ties go to the earlier indicator', () {
      final action = actionFor(perfect(billsPaidOnTime: 0, overdraftDays: 99));
      expect(action.indicator, HealthIndicator.billsOnTime);
    });
  });

  test('pillars hold two indicators each', () {
    for (final pillar in HealthPillar.values) {
      expect(
        HealthIndicator.values.where((i) => i.pillar == pillar),
        hasLength(2),
      );
    }
  });
}
