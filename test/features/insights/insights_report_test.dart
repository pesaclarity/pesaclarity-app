import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/insights/insights_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/insights/application/insights_report.dart';

import '../../domain/fixtures.dart';

void main() {
  final october = YearMonth(2026, 10);
  final summary = InsightsSummary.of([
    inflow(
      at: eat(2026, 10, 1),
      amount: kes(100000),
      categoryType: CategoryType.income,
    ),
    entry(
      at: eat(2026, 10, 3),
      amount: kes(12000),
      payeeId: 1,
      leakType: LeakType.lifestyle,
    ),
    entry(
      at: eat(2026, 9, 3),
      amount: kes(4000),
      payeeId: 1,
      leakType: LeakType.lifestyle,
    ),
  ], month: october);

  test('fits everything on one page, even with many tags', () async {
    final report = InsightsReport(
      summary: summary,
      createdAt: DateTime.utc(2026, 10, 26, 15),
      health: HealthIndex.compute(
        HealthInputs(month: YearMonth(2026, 9), incomeMinor: kes(90000)),
      ),
      healthChange: -2,
      tags: [
        for (var i = 0; i < 20; i++)
          (name: 'tag $i', spendingMinor: kes(1000 * (20 - i))),
        (name: 'safari ☀', spendingMinor: 0),
      ],
    );
    final bytes = await renderInsightsReport(report);
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF-'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
    expect(report.fileName, 'pesa-clarity-report-2026-10.pdf');
  });

  test('describes the change in leakage in plain words', () {
    expect(
      leakageSentence(summary, previousMonthName: 'September'),
      'Up 8,000 on September. Cutting half frees 6,000 a month.',
    );
    expect(healthChangeSentence(null), '');
    expect(healthChangeSentence(-2), ' Down 2 on the month before.');
  });

  test('sorts tags by spending, largest first', () {
    expect(tagSpends(const {}, const {}), isEmpty);
  });
}
