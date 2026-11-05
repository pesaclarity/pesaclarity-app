import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/business_report.dart';
import 'package:pesaclarity/src/domain/books/report_setup.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/business_insights/application/report_content.dart';

void main() {
  final today = CalendarDate(2026, 11, 5);

  group('periods', () {
    test('this month is compared with the same days of the month before', () {
      final p = periodFor(ReportRange.thisMonth, today);
      expect(p.from, CalendarDate(2026, 11, 1));
      expect(p.to, CalendarDate(2026, 11, 6));
      final c = comparisonFor(p);
      expect(c.from, CalendarDate(2026, 10, 1));
      expect(c.to, CalendarDate(2026, 10, 6));
      expect(c.label, 'October');
    });

    test('last month is compared with the whole month before it', () {
      final c = comparisonFor(periodFor(ReportRange.lastMonth, today));
      expect(c.from, CalendarDate(2026, 9, 1));
      expect(c.to, CalendarDate(2026, 10, 1));
      expect(c.label, 'September');
    });

    test('3 months is compared with the 3 months before', () {
      final p = periodFor(ReportRange.threeMonths, today);
      expect(p.from, CalendarDate(2026, 9, 1));
      final c = comparisonFor(p);
      expect(c.from, CalendarDate(2026, 6, 1));
      expect(c.label, 'the 3 months before');
    });

    test('dates that do not start a month compare with the days before', () {
      final p = ReportPeriod(
        CalendarDate(2026, 10, 10),
        CalendarDate(2026, 10, 20),
        '',
      );
      final c = comparisonFor(p);
      expect(c.from, CalendarDate(2026, 9, 30));
      expect(c.to, CalendarDate(2026, 10, 10));
    });

    test('reads as people say it', () {
      expect(
        periodText(periodFor(ReportRange.lastMonth, today), thisYear: 2026),
        '1 to 31 October',
      );
      expect(
        periodText(periodFor(ReportRange.threeMonths, today), thisYear: 2026),
        '1 September to 5 November',
      );
      expect(
        periodText(
          ReportPeriod(
            CalendarDate(2025, 12, 20),
            CalendarDate(2026, 1, 3),
            '',
          ),
        ),
        '20 December 2025 to 2 January 2026',
      );
    });
  });

  group('saved reports', () {
    test('keep who, sections and range', () {
      final settings = const ReportSettings()
          .withSaved(
            const ReportSetup(
              name: 'Monthly Sacco report',
              audience: ReportAudience.sacco,
              sections: {ReportSection.profitAndLoss, ReportSection.balance},
            ),
          )
          .copyWith(
            cover: const ReportCover(owner: 'Wanjiru K.', place: 'Gikomba'),
          );
      final back = ReportSettings.fromJson(settings.toJson());
      final s = back.saved.single;
      expect(s.name, 'Monthly Sacco report');
      expect(s.range, ReportRange.lastMonth);
      expect(s.sections, {ReportSection.profitAndLoss, ReportSection.balance});
      expect(
        back.cover.line('Vegetable stall'),
        'Vegetable stall · Wanjiru K. · Gikomba',
      );
    });

    test('keep their own dates', () {
      final s = ReportSetup.fromJson(
        ReportSetup(
          name: 'Harvest',
          audience: ReportAudience.me,
          sections: ReportAudience.me.sections,
          range: null,
          from: CalendarDate(2026, 8, 1),
          to: CalendarDate(2026, 8, 15),
        ).toJson(),
      )!;
      expect(s.range, isNull);
      final p = s.periodOn(today);
      expect(p.from, CalendarDate(2026, 8, 1));
      expect(p.to, CalendarDate(2026, 8, 15));
    });

    test('a report of the same name replaces the old one', () {
      const a = ReportSetup(
        name: 'Mine',
        audience: ReportAudience.me,
        sections: {ReportSection.insights},
      );
      const b = ReportSetup(
        name: 'mine',
        audience: ReportAudience.accountant,
        sections: {ReportSection.cashBook},
      );
      final s = const ReportSettings().withSaved(a).withSaved(b);
      expect(s.saved.single.audience, ReportAudience.accountant);
    });

    test('an accountant gets every section', () {
      expect(ReportAudience.accountant.sections, ReportSection.values.toSet());
      expect(
        ReportAudience.sacco.sections,
        isNot(contains(ReportSection.cashBook)),
      );
    });
  });

  test('CSV keeps money as plain numbers and quotes what needs it', () {
    final doc = ReportDocument(
      title: 'Business report',
      business: 'Vegetable stall',
      coverLine: 'Vegetable stall · Gikomba',
      period: periodFor(ReportRange.lastMonth, today),
      made: today,
      currency: 'KES',
      blocks: const [
        ReportTable(
          'Profit and loss',
          columns: ['', 'Amount'],
          rows: [
            ['Sales', 2450000],
            ['Rent, water and power', -220050],
          ],
          total: ['Profit', 2229950],
        ),
        ReportNotes('Insights', ['=1+1 is not a formula here.']),
      ],
    );
    final csv = reportCsv(doc);
    expect(csv, contains('Sales,24500.00\r\n'));
    expect(csv, contains('"Rent, water and power",-2200.50\r\n'));
    expect(csv, contains('Profit,22299.50\r\n'));
    expect(csv, contains("'=1+1 is not a formula here."));
    expect(csv, contains('Item,Amount\r\n'));
    expect(
      doc.fileName('csv'),
      'vegetable-stall-report-2026-10-01-to-2026-10-31.csv',
    );
  });

  test('insights speak from the records', () {
    final lines = businessInsights(
      byWeekday: [100, 100, 100, 100, 100, 500, 0],
      pnl: const ProfitAndLoss(income: [], costs: []),
      sold: const [],
      moneyInMinor: 3200000,
      moneyOutMinor: 2750000,
      customersOverTwoWeeks: 2,
      owedOverTwoWeeksMinor: 150000,
      closes: 6,
      closesMatched: 5,
      runningLow: const ['Onions'],
      plain: (m) => '${m ~/ 100}',
    );
    expect(lines, [
      'Saturday is your best day, with 50% of sales.',
      'Money in 32000 and out 27500, so you are 4500 ahead.',
      '2 customers owe 1500 for over two weeks. A reminder often helps.',
      'Onions is running low.',
      'Your drawer matched 5 of the last 6 closes.',
    ]);
  });
}
