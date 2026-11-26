import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_answer.dart';
import 'package:pesaclarity/src/features/slm_experiment/domain/slm_facts.dart';
import 'package:pesaclarity/src/features/slm_experiment/presentation/slm_experiment_screen.dart';

void main() {
  group('SlmAnswer.parse', () {
    test('reads the chart line and the words after it', () {
      final a = SlmAnswer.parse(
        '{"chart":"line","data":"months_trend","period":"last_3_months"}\n'
        'You spent more in Oct.',
      );
      expect(a.choice!.chart, SlmChart.line);
      expect(a.choice!.data, SlmData.months_trend);
      expect(a.choice!.period, SlmPeriod.last_3_months);
      expect(a.choice!.draws, isTrue);
      expect(a.text, 'You spent more in Oct.');
    });

    test('none draws nothing', () {
      final a = SlmAnswer.parse(
        '{"chart":"none","data":"none","period":"this_month"}\nNot sure.',
      );
      expect(a.choice!.draws, isFalse);
    });

    test('anything off the schema: text only, without the broken line', () {
      for (final bad in [
        '{"chart":"pie","data":"fees","period":"this_month"}\nWords.',
        '{"chart":"bar","data":"fees"}\nWords.',
        '{"chart":"bar","data":"fees","period":"today"}\nWords.',
        '{"chart":"bar","data":"fees","period":"this_month","x":1}\nWords.',
        '{"chart": bar\nWords.',
      ]) {
        final a = SlmAnswer.parse(bad);
        expect(a.choice, isNull, reason: bad);
        expect(a.text, 'Words.', reason: bad);
      }
      expect(SlmAnswer.parse('Just words.').text, 'Just words.');
    });

    test('while it streams, the chart line is hidden', () {
      expect(slmShownWhileRunning('{"chart":"ba'), '');
      expect(slmShownWhileRunning('{"chart":"bar"}\nRent'), 'Rent');
      expect(slmShownWhileRunning('Rent is'), 'Rent is');
    });
  });

  group('ungroundedNumbers', () {
    const facts = '- Rent: KES 15,000\n- Food: KES 1,200.50\n- 20 Nov 2026';
    test('numbers from the facts pass, with or without commas', () {
      expect(
        ungroundedNumbers(
          'Rent KES 15,000, food KES 1,200.50 on 20 Nov.',
          facts,
        ),
        isEmpty,
      );
      expect(ungroundedNumbers('Rent was KES 15000.', facts), isEmpty);
    });
    test('a number the facts do not have is flagged', () {
      expect(ungroundedNumbers('You could save KES 3,000.', facts), ['3,000']);
      expect(ungroundedNumbers('About 40% of it.', facts), ['40']);
    });
  });

  test('chart points come from the records, not the model', () {
    final today = CalendarDate(2026, 11, 20);
    LedgerEntry e(int id, CalendarDate d, int minor, {bool inflow = false}) =>
        LedgerEntry(
          id: id,
          accountId: 1,
          occurredAt: d.startInstant.add(const Duration(hours: 9)),
          amountMinor: minor,
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: inflow ? TransactionKind.received : TransactionKind.till,
          categoryId: inflow ? null : 1,
          categoryType: inflow ? CategoryType.income : CategoryType.expense,
          payeeId: 1,
          payeeName: 'DEMO SHOP',
          feeMinor: inflow ? 0 : 1000,
        );
    final input = SlmFactsInput(
      today: today,
      lastPayday: CalendarDate(2026, 11, 15),
      categoryNames: const {1: 'Food'},
      entries: [
        e(1, CalendarDate(2026, 10, 5), 200000),
        e(2, CalendarDate(2026, 11, 3), 300000),
        e(3, CalendarDate(2026, 11, 15), 5000000, inflow: true),
        e(4, CalendarDate(2026, 11, 16), 100000),
      ],
      budgets: const [SlmBudget('Food', 350000, 400000)],
    );
    List<SlmPoint> p(SlmChart c, SlmData d, SlmPeriod w) =>
        slmChartPoints(input, SlmChoice(c, d, w));
    final cats = p(SlmChart.bar, SlmData.top_categories, SlmPeriod.this_month);
    expect(cats.single.label, 'Food');
    expect(cats.single.amountMinor, 400000);
    final sincePay = p(
      SlmChart.bar,
      SlmData.top_payees,
      SlmPeriod.since_payday,
    );
    expect(sincePay.single.amountMinor, 100000);
    final trend = p(
      SlmChart.line,
      SlmData.months_trend,
      SlmPeriod.last_3_months,
    );
    expect(trend, hasLength(4));
    expect(trend[2].amountMinor, 200000);
    expect(trend[3].amountMinor, 400000);
    final weeks = p(SlmChart.bar, SlmData.in_out_weeks, SlmPeriod.since_payday);
    expect(weeks.first.amountMinor, 5000000);
    expect(weeks.first.secondMinor, 100000);
    final budget = p(
      SlmChart.bar,
      SlmData.budget_vs_spent,
      SlmPeriod.this_month,
    );
    expect(budget.single.secondMinor, 350000);
    final fees = p(SlmChart.donut, SlmData.fees, SlmPeriod.this_month);
    expect(fees.first.amountMinor, 2000);
    expect(p(SlmChart.none, SlmData.none, SlmPeriod.this_month), isEmpty);
  });
}
