import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/insights/application/insights_report.dart';
import 'package:pesaclarity/src/features/insights/application/report_sharer.dart';
import 'package:pesaclarity/src/features/insights/presentation/insights_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

class _FakeSharer implements ReportSharer {
  final shared = <({Uint8List bytes, String fileName, String subject})>[];

  @override
  Future<void> sharePdf(
    Uint8List bytes, {
    required String fileName,
    required String subject,
  }) async => shared.add((bytes: bytes, fileName: fileName, subject: subject));

  @override
  Future<void> shareFile(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) async => shared.add((bytes: bytes, fileName: fileName, subject: subject));
}

Future<void> _seed(AppDatabase db) async {
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  final salary = await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          name: 'Test salary',
          type: CategoryType.income,
        ),
      );
  final outings = await db
      .into(db.payees)
      .insert(
        PayeesCompanion.insert(
          displayName: 'Example Lounge',
          leakType: const Value(LeakType.lifestyle),
        ),
      );
  final friend = await db
      .into(db.payees)
      .insert(
        PayeesCompanion.insert(
          displayName: 'John',
          leakType: const Value(LeakType.friends),
        ),
      );

  Future<int> add(
    DateTime at,
    int shillings, {
    TransactionDirection direction = TransactionDirection.outflow,
    TransactionKind kind = TransactionKind.till,
    int? payeeId,
    int? categoryId,
    int fee = 0,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: at,
          amountMinor: kes(shillings),
          direction: direction,
          kind: Value(kind),
          payeeId: Value(payeeId),
          categoryOverrideId: Value(categoryId),
          feeMinor: Value(kes(fee)),
          source: TransactionSource.manual,
        ),
      );

  await add(
    eat(2026, 10, 1),
    100000,
    direction: TransactionDirection.inflow,
    kind: TransactionKind.received,
    categoryId: salary,
  );
  final lounge = await add(eat(2026, 10, 10), 12000, payeeId: outings);
  await add(
    eat(2026, 10, 12),
    5000,
    kind: TransactionKind.sent,
    payeeId: friend,
  );
  await add(eat(2026, 10, 14), 20000, fee: 30);
  await add(eat(2026, 9, 10), 6000, payeeId: outings);

  final tag = await db
      .into(db.tags)
      .insert(TagsCompanion.insert(name: 'roadtrip'));
  await db
      .into(db.transactionTags)
      .insert(
        TransactionTagsCompanion.insert(transactionId: lounge, tagId: tag),
      );
}

final _health = HealthIndex.compute(
  HealthInputs(
    month: YearMonth(2026, 9),
    incomeMinor: kes(100000),
    spendingMinor: kes(80000),
    billsDue: 2,
    billsPaidOnTime: 2,
    essentialsMinor: kes(40000),
    savingsBalanceMinor: kes(60000),
    savedMinor: kes(5000),
    debtPaymentsMinor: kes(10000),
    leakageMinor: kes(25000),
    plannedCategories: 4,
    categoriesWithinBudget: 3,
  ),
);

void main() {
  late AppDatabase db;
  late _FakeSharer sharer;
  late List<InsightsReport> reports;

  Future<void> pumpInsights(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Monday 26 October 2026, 18:00 EAT.
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 15)),
          healthIndexProvider.overrideWith(
            (ref) async => HealthOnHome(_health, 4),
          ),
          reportSharerProvider.overrideWithValue(sharer),
          reportRendererProvider.overrideWithValue((report) async {
            reports.add(report);
            return Uint8List.fromList(latin1.encode('%PDF-1.4'));
          }),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: GoRouter(
            initialLocation: '/insights',
            routes: [
              GoRoute(
                path: '/insights',
                builder: (_, _) => const InsightsScreen(),
              ),
              GoRoute(
                path: '/activity',
                builder: (_, state) =>
                    Scaffold(body: Text('Activity ${state.uri.query}')),
              ),
              GoRoute(
                path: '/home/profile/accounts',
                builder: (_, _) => const Scaffold(body: Text('My accounts')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    db = openTestDatabase();
    sharer = _FakeSharer();
    reports = [];
  });

  testAppWidgets('shows what changed, spending, leakage, health and tags', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    // October to the 26th against 1-26 September.
    expect(find.text('What changed'), findsOneWidget);
    expect(find.text('Uncategorised up 31,000 on last month'), findsOneWidget);
    expect(find.text('37,000 so far this month'), findsOneWidget);
    expect(find.text('Fees 30 so far'), findsOneWidget);
    expect(find.text('30 more than last month'), findsOneWidget);
    expect(find.text('Money in 100,000 so far'), findsOneWidget);

    // Spending this month by category, and so far against September.
    await tester.scrollUntilVisible(find.text('This month so far'), 200);
    expect(
      find.bySemanticsLabel(RegExp('Spending by category: .*Fees 30')),
      findsOneWidget,
    );
    expect(find.text('31,030 over last month'), findsOneWidget);
    expect(find.text('Spending, last 6 months'), findsNothing);

    await tester.scrollUntilVisible(find.text('Leakage in October'), 200);
    // 12,000 lifestyle + 5,000 friends + 30 in fees.
    expect(find.text('17,030'), findsOneWidget);
    expect(find.text('17% of income'), findsOneWidget);
    expect(
      find.text('Up 11,030 on September. Cutting half frees 8,500 a month.'),
      findsOneWidget,
    );
    expect(find.text('Lifestyle 12,000'), findsOneWidget);
    expect(find.text('Where it goes'), findsNothing);

    await tester.scrollUntilVisible(find.text('What helps most'), 200);
    expect(find.text('Financial Health Index'), findsOneWidget);
    expect(find.text('${_health.score}'), findsOneWidget);
    expect(find.text(_health.bestAction!.message), findsOneWidget);
    expect(find.text('Spend'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('#roadtrip'), 200);
    expect(find.text('Tags in October'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testAppWidgets('a finding opens the transactions behind it', (tester) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    await tester.tap(find.text('Fees 30 so far'));
    await tester.pumpAndSettle();
    expect(
      find.text('Activity type=fees&from=2026-10-01&to=2026-10-26'),
      findsOneWidget,
    );
  });

  testAppWidgets('a category in the ring opens its transactions', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    await tester.scrollUntilVisible(find.byKey(const Key('slice-0')), 200);
    await tester.tap(find.byKey(const Key('slice-0')));
    await tester.pumpAndSettle();
    expect(
      find.text('Activity from=2026-10-01&to=2026-10-26&category=none'),
      findsOneWidget,
    );
  });

  testAppWidgets('a health pillar opens its indicators', (tester) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    await tester.scrollUntilVisible(find.byKey(const Key('pillar-save')), 200);
    await tester.ensureVisible(find.byKey(const Key('pillar-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pillar-save')));
    await tester.pumpAndSettle();
    expect(find.text('Emergency cushion'), findsOneWidget);
    expect(find.text('Savings rate'), findsOneWidget);
    expect(
      find.textContaining('Each pillar is worth 25 points'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pillar-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('Activity from=2026-09-01&to=2026-09-30'), findsOneWidget);
  });

  testAppWidgets('Report builds the PDF and opens the share sheet', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    final report = reports.single;
    expect(report.summary.current.leakageMinor, kes(17030));
    expect(report.health, same(_health));
    expect(report.healthChange, 4);
    expect(report.tags.single, (name: 'roadtrip', spendingMinor: kes(12000)));

    final shared = sharer.shared.single;
    expect(shared.fileName, 'pesa-clarity-report-2026-10.pdf');
    expect(shared.subject, 'Pesa Clarity report, October 2026');
    expect(latin1.decode(shared.bytes), '%PDF-1.4');
  });

  testAppWidgets('explains itself before there are transactions', (
    tester,
  ) async {
    await pumpInsights(tester);
    expect(find.text('Your insights show here'), findsOneWidget);
    expect(find.text('Financial Health Index'), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('Tag a transaction'),
      200,
    );
    expect(find.textContaining('Tag a transaction'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Choose my accounts'), -200);
    await tester.tap(find.text('Choose my accounts'));
    await tester.pumpAndSettle();
    expect(find.text('My accounts'), findsOneWidget);
  });

  testAppWidgets('switches the spending charts between week, month and year', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // Monday the 26th: nothing spent yet this week, nothing last week.
    expect(find.text('This week so far'), findsOneWidget);
    expect(
      find.text('Spending this week shows here as it comes in.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('This year so far'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Spending by category: .*Fees 30')),
      findsOneWidget,
    );

    // The year shows month by month; a month opens its spending.
    await tester.scrollUntilVisible(find.text('Spending, last 6 months'), 200);
    await tester.ensureVisible(find.byKey(const Key('trend-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trend-4')));
    await tester.pumpAndSettle();
    expect(
      find.text('Activity type=spending&from=2026-09-01&to=2026-09-30'),
      findsOneWidget,
    );
  });
}
