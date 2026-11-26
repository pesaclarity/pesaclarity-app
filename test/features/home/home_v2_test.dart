import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/budget/until_next_money.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/home/home_period.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/presentation/line_questions.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/home_period_providers.dart';
import 'package:pesaclarity/src/features/home/application/home_safe_provider.dart';
import 'package:pesaclarity/src/features/home/application/things_to_sort_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/insights/presentation/spending_charts_card.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

/// Sunday 22 November 2026, 15:00 EAT.
final _now = DateTime.utc(2026, 11, 22, 12);
final _today = CalendarDate(2026, 11, 22);

final _history = [
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
    fee: kes(87),
    categoryType: CategoryType.expense,
  ),
  entry(id: 3, at: eat(2026, 11, 21, 8), amount: kes(3000), transferPairId: 4),
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
    at: eat(2026, 11, 3, 9),
    amount: kes(5000),
    categoryType: CategoryType.expense,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<SortThing> things = const [],
  List<LedgerEntry> entries = const [],
  HomeSafe safe = const HomeSafe(),
  CalendarDate? payday,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(openTestDatabase()),
        clockProvider.overrideWithValue(() => _now),
        readsMpesaHereProvider.overrideWithValue(const AsyncData(false)),
        pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
        homePeriodViewProvider.overrideWith(
          (ref, period) async =>
              HomePeriodView.of(entries, period: period, today: _today),
        ),
        homeSincePaydayViewProvider.overrideWith(
          (ref) async => HomePeriodView.of(
            entries,
            period: HomePeriod.thisMonth,
            today: _today,
            payday: payday,
          ),
        ),
        thingsToSortProvider.overrideWithValue(things),
        overBudgetAlertsProvider.overrideWithValue(const []),
        homeSafeProvider.overrideWithValue(safe),
        cashFlowForecastProvider.overrideWith((ref) async => null),
        healthIndexProvider.overrideWith((ref) async => null),
        upcomingBillsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('safe to spend first, then this month in and out with fees', (
    tester,
  ) async {
    await _pump(tester, entries: _history);

    // Safe to spend leads, above this month's figures.
    expect(
      tester.getTopLeft(find.byKey(const Key('home-safe'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('home-in-out'))).dy),
    );
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('6,500'), findsWidgets);
    // This month: 1,340 + 87 of fees + 620 + 5,000 on the 3rd; the own
    // transfer is in no total.
    expect(find.text('7,047'), findsOneWidget);
    expect(find.text('-547'), findsOneWidget);
    expect(find.text('of which fees KES 87'), findsOneWidget);
    expect(find.byKey(const Key('home-figure-moneyIn')), findsOneWidget);
    // Periods, days, charts and the month's forecast are elsewhere.
    expect(find.text('This week'), findsNothing);
    expect(find.text('See all in Activity'), findsNothing);
    expect(find.text('More about this month'), findsNothing);
    expect(find.text('Charts'), findsNothing);
    expect(find.byType(SpendingChartsSection), findsNothing);
    // Nothing to sort: no row.
    expect(find.byKey(const Key('home-things-to-sort')), findsNothing);
  });

  testAppWidgets('things to sort shows its count only when there is any', (
    tester,
  ) async {
    await _pump(
      tester,
      entries: _history,
      things: const [
        SortThing(SortGroup.needsYou, '3 not yet sorted'),
        SortThing(SortGroup.needsYou, 'Food at 80%'),
        SortThing(SortGroup.whenYouHaveTime, 'weekly check-in'),
        SortThing(SortGroup.whenYouHaveTime, 'support'),
      ],
    );
    expect(find.text('Things to sort (4)'), findsOneWidget);
    expect(
      find.text('3 not yet sorted, Food at 80% and 2 more'),
      findsOneWidget,
    );
  });

  testAppWidgets('safe to spend is the red lead card', (tester) async {
    final until = UntilNextMoney.calculate(
      today: _today,
      basis: NextMoneyBasis.rhythm,
      onHandAtStartMinor: 1000000,
      billsMinor: 0,
      spentTodayMinor: 0,
      paceMinor: 100000,
      usualTodayMinor: 100000,
      historyDays: 60,
      nextMoney: CalendarDate(2026, 11, 30),
    );
    await _pump(
      tester,
      entries: _history,
      safe: HomeSafe(untilNext: until),
    );
    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.textContaining('a day for'), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('home-safe'))),
      isA<HeroFigureCard>(),
    );
    expect(
      tester.widget<HeroFigureCard>(find.byType(HeroFigureCard)).belowZero,
      isFalse,
    );
  });

  testAppWidgets('a new person sees zeros and how to start', (tester) async {
    await _pump(tester);
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('Read my messages'), findsOneWidget);
    expect(find.text('Add by hand'), findsOneWidget);
    expect(find.text('Charts'), findsNothing);
  });

  testAppWidgets('the eye on the lead card hides this month too', (
    tester,
  ) async {
    await _pump(tester, entries: _history);
    expect(find.text('7,047'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home-safe')),
        matching: find.byKey(const Key('amounts-eye')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7,047'), findsNothing);
    expect(find.textContaining('of which fees KES 87'), findsNothing);
  });

  testAppWidgets('without a regular income it is this month', (tester) async {
    await _pump(tester, entries: _history);
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('1 – 22 Nov'), findsOneWidget);
  });

  testAppWidgets('with a payday it is since payday, salary included', (
    tester,
  ) async {
    final salary = inflow(
      id: 9,
      at: eat(2026, 10, 31, 7),
      amount: kes(110000),
      categoryType: CategoryType.income,
    );
    await _pump(
      tester,
      entries: [..._history, salary],
      payday: CalendarDate(2026, 10, 31),
    );
    expect(find.text('SINCE PAYDAY'), findsOneWidget);
    expect(find.text('THIS MONTH'), findsNothing);
    expect(find.text('31 Oct – 22 Nov'), findsOneWidget);
    expect(find.text('116,500'), findsOneWidget);
    expect(find.text('109,453'), findsOneWidget);
    // The eye hides these figures too.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home-safe')),
        matching: find.byKey(const Key('amounts-eye')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('116,500'), findsNothing);
    expect(find.text('109,453'), findsNothing);
  });
}
