import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/plan/plan_groups.dart';
import 'package:pesaclarity/src/features/plan/presentation/payday_screen.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// Thursday 26 November 2026, 09:00 EAT.
final now = DateTime.utc(2026, 11, 26, 6);

/// Machado, Oliveira and Fernandes (2009) at full severity, on linear RGB.
const protanopia = [
  [0.152286, 1.052583, -0.204868],
  [0.114503, 0.786281, 0.099216],
  [-0.003882, -0.048116, 1.051998],
];
const deuteranopia = [
  [0.367322, 0.860646, -0.227968],
  [0.280085, 0.672501, 0.047413],
  [-0.011820, 0.042940, 0.968881],
];

double _linear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

/// [colour] as someone with [deficiency] sees it, in CIELAB.
List<double> simulatedLab(Color colour, List<List<double>> deficiency) {
  final rgb = [colour.r, colour.g, colour.b].map(_linear).toList();
  final s = [
    for (final row in deficiency)
      (row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2]).clamp(0.0, 1.0),
  ];
  final x = (0.4124 * s[0] + 0.3576 * s[1] + 0.1805 * s[2]) / 0.95047;
  final y = 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2];
  final z = (0.0193 * s[0] + 0.1192 * s[1] + 0.9505 * s[2]) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

/// The CIE76 colour difference between two CIELAB colours.
double labDistance(List<double> a, List<double> b) => math.sqrt(
  [for (var i = 0; i < 3; i++) (a[i] - b[i]) * (a[i] - b[i])]
      .reduce((p, q) => p + q),
);

Future<int> categoryId(AppDatabase db, String key) async => (await (db.select(
  db.categories,
)..where((c) => c.key.equals(key))).getSingle()).id;

Future<void> addBill(
  AppDatabase db,
  String name,
  String key,
  int shillings, {
  required DateTime start,
}) async => db
    .into(db.recurring)
    .insert(
      RecurringCompanion.insert(
        name: name,
        categoryId: Value(await categoryId(db, key)),
        amountMinor: shillings * 100,
        frequency: RecurrenceFrequency.monthly,
        startDate: start,
      ),
    );

Future<void> spend(
  AppDatabase db,
  int account,
  String key,
  int shillings,
  DateTime at,
) async => db
    .into(db.transactions)
    .insert(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: at,
        amountMinor: shillings * 100,
        direction: TransactionDirection.outflow,
        kind: const Value(TransactionKind.till),
        categoryOverrideId: Value(await categoryId(db, key)),
        source: TransactionSource.sms,
      ),
    );

Future<void> seedNovember(AppDatabase db, {DateTime? start}) async {
  final from = start ?? DateTime.utc(2026, 11);
  await addBill(
    db,
    'Salary',
    'salary',
    181600,
    start: DateTime.utc(2026, 11, 25),
  );
  await addBill(
    db,
    'Rent',
    'rent',
    15000,
    start: from.add(const Duration(days: 4)),
  );
  await addBill(db, 'Eating out', 'eating_out', 5000, start: from);
  await addBill(db, 'Transport', 'transport', 12000, start: from);
  final account = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026),
        ),
      );
  await spend(db, account, 'rent', 15000, DateTime.utc(2026, 11, 5, 9));
  await spend(db, account, 'eating_out', 6420, DateTime.utc(2026, 11, 10, 9));
  await spend(db, account, 'transport', 6960, DateTime.utc(2026, 11, 12, 9));
}

Future<void> pumpScreen(
  WidgetTester tester,
  AppDatabase db,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testAppWidgets('shows the plan against income, by category', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PlanScreen());

    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Planned of expected income'), findsOneWidget);
    expect(find.text('181,600'), findsWidgets);
    expect(find.text('32,000'), findsOneWidget);
    expect(find.text('Living 32,000'), findsOneWidget);

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Over'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('15,000 of 15,000'), findsOneWidget);
    expect(find.text('6,420 of 5,000'), findsOneWidget);

    expect(find.text('Surplus 149,600'), findsOneWidget);
    expect(find.text('All to savings'), findsOneWidget);

    // Salary was due yesterday, so payday autopilot is on offer.
    expect(find.text('Payday: split 181,600'), findsOneWidget);

    await tester.tap(find.text('Pending only'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
    expect(find.text('Show all'), findsOneWidget);
  });

  testAppWidgets('draws the income bar at its full height', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PlanScreen());

    final bar = find.byWidgetPredicate(
      (w) => w is SizedBox && w.height == 10 && w.child is Row,
    );
    final segments = find.descendant(
      of: bar,
      matching: find.byType(ColoredBox),
    );
    expect(segments, findsWidgets);
    for (var i = 0; i < segments.evaluate().length; i++) {
      expect(tester.getSize(segments.at(i)).height, 10);
    }
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('gives every plan group its own colour in $name', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final colours = {
        for (final g in PlanGroup.values) planGroupColour(context, g),
      };
      expect(colours, hasLength(PlanGroup.values.length));
      // Only one may be a neutral grey: two greys read as one group.
      final greys = colours.where((c) => HSLColor.fromColor(c).saturation == 0);
      expect(greys, hasLength(lessThanOrEqualTo(1)));
      // And they stay apart with red-green colour blindness.
      for (final deficiency in [protanopia, deuteranopia]) {
        final seen = colours.map((c) => simulatedLab(c, deficiency)).toList();
        for (var i = 0; i < seen.length; i++) {
          for (var j = i + 1; j < seen.length; j++) {
            expect(
              labDistance(seen[i], seen[j]),
              greaterThan(12),
              reason: '${colours.elementAt(i)} and ${colours.elementAt(j)}',
            );
          }
        }
      }
    });
  }

  testAppWidgets('adds a one-off to the month', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PlanScreen());

    final add = find.byTooltip('Add to Nov 2026');
    await scrollTo(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('One-off'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('Name', type: TextFormField), 'Gift');
    await tester.enterText(
      fieldLabelled('Amount', type: TextFormField),
      '2,500',
    );
    await tapText(tester, 'Save');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Gift'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('34,500'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('34,500'), findsOneWidget);
  });

  testAppWidgets('closes finished months and carries unpaid bills', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => seedNovember(db, start: DateTime.utc(2026, 10)),
    );
    await pumpScreen(tester, db, const PlanScreen());

    // October's rent was never paid, so it is carried into November.
    await scrollTo(tester, find.textContaining('Carried forward'));
    expect(find.textContaining('Carried forward'), findsOneWidget);
    expect(find.text('15,000 of 30,000'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip('Previous month'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.textContaining('This month is closed'), findsOneWidget);
  });

  testAppWidgets('payday checklist ticks off each task', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seedNovember(db));
    await pumpScreen(tester, db, const PaydayScreen());

    expect(find.text('KES 181,600'), findsOneWidget);
    expect(find.text('Set aside'), findsOneWidget);
    expect(find.text('Day-to-day spending'), findsOneWidget);
    expect(find.text('Surplus to savings'), findsOneWidget);
    expect(find.textContaining('0 of 2 done'), findsOneWidget);

    await tester.tap(find.text('Day-to-day spending'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of 2 done'), findsOneWidget);
  });
}
