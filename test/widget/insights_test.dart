import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        child: MaterialApp(theme: AppTheme.light, home: const InsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    db = openTestDatabase();
    sharer = _FakeSharer();
    reports = [];
  });

  testAppWidgets('shows leakage, where it goes, trend, health and tags', (
    tester,
  ) async {
    await tester.runAsync(() => _seed(db));
    await pumpInsights(tester);

    expect(find.text('Leakage in October'), findsOneWidget);
    // 12,000 lifestyle + 5,000 friends + 30 in fees.
    expect(find.text('17,030'), findsOneWidget);
    expect(find.text('17% of income'), findsOneWidget);
    expect(
      find.text('Up 11,030 on September. Cutting half frees 8,500 a month.'),
      findsOneWidget,
    );
    expect(find.text('Where it goes'), findsOneWidget);
    expect(find.text('Lifestyle'), findsOneWidget);
    expect(find.text('12,000'), findsWidgets);
    expect(find.text('Fuliza fees'), findsOneWidget);
    expect(find.text('Spending, last 6 months'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Monthly spending: May 0, .*October 37,030'),
      ),
      findsOneWidget,
    );

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
    expect(find.text('Your leakages show here'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Tag a transaction'),
      200,
    );
    expect(find.textContaining('Tag a transaction'), findsOneWidget);
  });
}
