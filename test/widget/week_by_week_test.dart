import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/income/week_by_week.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/income/presentation/week_by_week_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _FakeRainyDayFund extends RainyDayFundController {
  final moves = <int>[];

  @override
  Future<RainyDayFund> build() async => const RainyDayFund();

  @override
  Future<void> move(int amountMinor) async => moves.add(amountMinor);
}

void main() {
  final today = CalendarDate(2026, 11, 4);
  WeekFlow week(int weeksAgo, int inKes, int outKes) => WeekFlow(
    start: weekStartOf(today).addDays(-7 * weeksAgo),
    inMinor: inKes * 100,
    outMinor: outKes * 100,
  );

  Future<_FakeRainyDayFund> open(WidgetTester tester, WeekByWeek plan) async {
    final fund = _FakeRainyDayFund();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weekByWeekProvider.overrideWith((ref) async => plan),
          rainyDayFundProvider.overrideWith(() => fund),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const WeekByWeekScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fund;
  }

  testWidgets('a good week offers to fill the rainy day fund', (tester) async {
    final fund = await open(
      tester,
      WeekByWeek(
        weeks: [
          for (var i = usualWeeksCount; i >= 1; i--) week(i, 4500, 4200),
          week(0, 6800, 4100),
        ],
        usualInMinor: 450000,
        usualOutMinor: 420000,
        fund: RainyDayFund([
          RainyDayMove(on: CalendarDate(2026, 10, 20), amountMinor: 320000),
        ]),
        today: today,
      ),
    );

    expect(find.text('This week · Mon 2 Nov – Sun 8 Nov'), findsOneWidget);
    expect(find.text('6,800'), findsOneWidget);
    expect(find.text('4,100'), findsOneWidget);
    expect(
      find.text(
        'A good week: 2,300 more than a usual one. '
        'Put 1,000 in your rainy day fund?',
      ),
      findsOneWidget,
    );
    expect(find.text('3,200 of 4,200'), findsOneWidget);
    expect(find.text('Last $weeksShown weeks'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rainy-day-add')));
    await tester.pump();
    expect(fund.moves, [100000]);
  });

  testWidgets('a lean week offers to take from it', (tester) async {
    final fund = await open(
      tester,
      WeekByWeek(
        weeks: [
          for (var i = usualWeeksCount; i >= 1; i--) week(i, 4500, 4200),
          week(0, 1000, 2500),
        ],
        usualInMinor: 450000,
        usualOutMinor: 420000,
        fund: RainyDayFund([
          RainyDayMove(on: CalendarDate(2026, 10, 20), amountMinor: 200000),
        ]),
        today: today,
      ),
    );

    expect(find.textContaining('A lean week so far'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rainy-day-take')));
    await tester.pump();
    expect(fund.moves, [-200000]);
  });
}
