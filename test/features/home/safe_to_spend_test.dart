import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/budget/until_next_money.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/income/make_it_last.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  group('safeToSpendTodayProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Monday 26 October 2026, 08:00 EAT.
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> category(String name, {required bool daily}) => db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: name,
            type: CategoryType.expense,
            isDailySpending: Value(daily),
          ),
        );

    test('is null without a day-to-day budget', () async {
      expect(await container.read(safeToSpendTodayProvider.future), isNull);
    });

    test('uses monthly budgets and this month\'s one-offs', () async {
      final food = await category('Food', daily: true);
      final rent = await category('Rent', daily: false);
      final account = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'M-Pesa',
              type: AccountType.mpesa,
              openingDate: DateTime.utc(2026),
            ),
          );

      Future<void> recurring(int categoryId, int amount, {DateTime? end}) => db
          .into(db.recurring)
          .insert(
            RecurringCompanion.insert(
              name: 'Line $amount',
              categoryId: Value(categoryId),
              amountMinor: amount,
              frequency: RecurrenceFrequency.monthly,
              startDate: DateTime.utc(2026),
              endDate: Value(end),
            ),
          );
      await recurring(food, 2500000);
      await recurring(rent, 4000000);
      await recurring(food, 999900, end: DateTime.utc(2026, 9, 30));
      await db
          .into(db.budgetItems)
          .insert(
            BudgetItemsCompanion.insert(
              month: 202610,
              name: 'Visitors',
              categoryId: Value(food),
              amountMinor: 500000,
              kind: BudgetItemKind.oneOff,
            ),
          );

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: DateTime.utc(2026, 10, 10, 9),
              amountMinor: 2400000,
              direction: TransactionDirection.outflow,
              categoryOverrideId: Value(food),
              source: TransactionSource.manual,
            ),
          );

      final result = await container.read(safeToSpendTodayProvider.future);
      expect(result, isNotNull);
      expect(result!.today, CalendarDate(2026, 10, 26));
      expect(result.budgetMinor, 3000000);
      expect(result.spentBeforeTodayMinor, 2400000);
      expect(result.weekdayLimitMinor, 100000);
    });
  });

  testWidgets('Home shows what is safe to spend today', (tester) async {
    final result = SafeToSpend(
      today: CalendarDate(2026, 10, 26),
      budgetMinor: 3000000,
      spentBeforeTodayMinor: 2400000,
      spentTodayMinor: 40000,
      weekdaysLeft: 5,
      weekendDaysLeft: 1,
      weekdayLimitMinor: 100000,
      weekendLimitMinor: 100000,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
          safeToSpendTodayProvider.overrideWith((ref) async => result),
          cashFlowForecastProvider.overrideWith((ref) async => null),
          healthIndexProvider.overrideWith((ref) async => null),
          upcomingBillsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KES 600'), findsOneWidget);
    expect(find.text('Safe to spend today · Weekday'), findsOneWidget);
    expect(find.text('Weekend days get 1,000'), findsOneWidget);
    expect(find.text("81% of this month's spending plan used"), findsOneWidget);
    expect(find.text('5,600'), findsOneWidget);
  });

  testWidgets('before there is anything to count, Home says when it will', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
          safeToSpendTodayProvider.overrideWith((ref) async => null),
          untilNextMoneyProvider.overrideWith((ref) async => null),
          cashFlowForecastProvider.overrideWith((ref) async => null),
          healthIndexProvider.overrideWith((ref) async => null),
          upcomingBillsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(
      find.text(
        'Shows once your messages have been read and Plan has a '
        'day-to-day budget.',
      ),
      findsOneWidget,
    );
    expect(find.text('Soon'), findsNWidgets(2));
    expect(find.text('Shows once Plan has a budget'), findsOneWidget);
    expect(find.text('Shows after two weeks of records'), findsOneWidget);
    expect(find.textContaining('—'), findsNothing);
    expect(find.textContaining('KES'), findsNothing);
  });

  testWidgets('Home plans until the next money for a student', (tester) async {
    final until = UntilNextMoney.calculate(
      today: CalendarDate(2026, 11, 14),
      basis: NextMoneyBasis.rhythm,
      onHandAtStartMinor: 500000,
      billsMinor: 150000,
      spentTodayMinor: 0,
      paceMinor: 40000,
      usualTodayMinor: 40000,
      historyDays: 60,
      nextMoney: CalendarDate(2026, 11, 24),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 14, 6)),
          pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
          safeToSpendTodayProvider.overrideWith((ref) async => null),
          untilNextMoneyProvider.overrideWith((ref) async => until),
          latestArrivalProvider.overrideWith(
            (ref) async => LedgerEntry(
              id: 3,
              accountId: 1,
              occurredAt: DateTime.utc(2026, 11, 13, 9),
              amountMinor: 500000,
              direction: TransactionDirection.inflow,
              kind: TransactionKind.received,
              payeeName: 'Test Mum',
            ),
          ),
          makeItLastProvider.overrideWith(_NoPin.new),
          purposeQueueProvider.overrideWith(
            (ref) async => [
              LedgerEntry(
                id: 8,
                accountId: 1,
                occurredAt: DateTime.utc(2026, 11, 13, 9),
                amountMinor: 300000,
                direction: TransactionDirection.inflow,
                kind: TransactionKind.received,
                payeeName: 'Test Wanjiku',
                needsPurpose: true,
              ),
            ],
          ),
          incomeSourcesProvider.overrideWith(
            () => _FixedSources({IncomeSource.support}),
          ),
          cashFlowForecastProvider.overrideWith((ref) async => null),
          healthIndexProvider.overrideWith((ref) async => null),
          upcomingBillsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('until-next-money')), findsOneWidget);
    // 5,000 less a 500 buffer and 1,500 of rent, over 10 days.
    expect(find.text('KES 300'), findsOneWidget);
    // The red card's caption: one line each.
    expect(
      find.text(
        'Until about Tue 24 Nov, when money usually comes\n'
        '5,000 on hand · 1,500 for bills',
      ),
      findsOneWidget,
    );
    // On hand shows once, in the caption; the tile says when money comes.
    expect(find.text('On hand'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-next-money')),
        matching: find.text('Tue 24 Nov'),
      ),
      findsOneWidget,
    );
    // Not enough history for a pace yet.
    expect(find.text('Shows after two weeks of records'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(find.byKey(const Key('home-what-was-this')), findsOneWidget);
    expect(find.text('Make it last'), findsOneWidget);
    expect(
      find.text('5,000 came in from Test Mum · until Mon 23 Nov'),
      findsOneWidget,
    );
    expect(find.text('3,000 from Test Wanjiku'), findsOneWidget);
    // Only the red card's figure carries the currency code.
    expect(find.textContaining('KES'), findsOneWidget);

    // The eye on the card hides every amount on Home.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('until-next-money')),
        matching: find.byKey(const Key('amounts-eye')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('KES 300'), findsNothing);
    expect(
      find.textContaining('••••• on hand · ••••• for bills'),
      findsOneWidget,
    );
    expect(
      find.text('••••• came in from Test Mum · until Mon 23 Nov'),
      findsOneWidget,
    );
    expect(find.text('••••• from Test Wanjiku'), findsOneWidget);
  });
}

class _FixedSources extends IncomeSourcesController {
  _FixedSources(this.picked);

  final Set<IncomeSource> picked;

  @override
  Future<IncomeSources> build() async => IncomeSources(picked);
}

class _NoPin extends MakeItLastController {
  @override
  Future<MakeItLastPin?> build() async => null;
}
