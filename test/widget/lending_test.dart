import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../helpers/goals_harness.dart';
import '../helpers/test_app.dart';

void main() {
  Future<int> lend(AppDatabase db) => DriftLendingRepository(db).add(
    person: 'John Kamau',
    amountMinor: 500000,
    lentOn: CalendarDate(2026, 10, 3),
    dueDate: CalendarDate(2026, 10, 20),
  );

  testAppWidgets('shares a polite reminder for money lent', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => lend(db));
    final sharer = FakeReminderSharer();
    await pumpGoals(
      tester,
      db: db,
      location: AppRoutes.lending,
      sharer: sharer,
    );

    expect(find.text('Owed to you'), findsOneWidget);
    expect(find.text('John Kamau'), findsOneWidget);
    expect(find.text('Lent 3 Oct · was due 20 Oct'), findsOneWidget);

    await tester.tap(find.text('John Kamau'));
    await settle(tester);
    await tester.tap(find.text('Send a reminder'));
    await settle(tester);
    expect(find.text('Reminder for John Kamau'), findsOneWidget);
    expect(sharer.shared, isEmpty, reason: 'nothing is sent before Share');

    await tester.tap(find.text('Share'));
    await settle(tester);
    expect(sharer.shared.single, startsWith('Hi John, hope you are well.'));
  });

  testAppWidgets('records a part payment, then settles', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => lend(db));
    await pumpGoals(tester, db: db, location: AppRoutes.lending);

    await tester.tap(find.text('John Kamau'));
    await settle(tester);
    await tester.tap(find.text('Record a payment'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount paid'),
      '6,000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await settle(tester);
    expect(find.text('Up to KES 5,000.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount paid'),
      '2,000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await settle(tester);
    expect(find.text('3,000'), findsNWidgets(2));
    expect(find.textContaining('KES 2,000 paid'), findsOneWidget);

    await tester.tap(find.text('John Kamau'));
    await settle(tester);
    await tester.tap(find.text('Mark as paid back'));
    await settle(tester);
    expect(find.text('Paid back · lent 3 Oct'), findsOneWidget);
    final loan = (await tester.runAsync(DriftLendingRepository(db).lent))!;
    expect(loan.single.payments, hasLength(2));
  });

  testAppWidgets('borrowing from family adds an interest-free debt', (
    tester,
  ) async {
    final db = openTestDatabase();
    await pumpGoals(tester, db: db, location: AppRoutes.lending);

    await tester.tap(find.text('Add'));
    await settle(tester);
    await tester.tap(find.text('I borrowed'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Borrowed from'),
      'Aunt Wanjiru',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '21,000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);

    expect(find.text('You borrowed'), findsOneWidget);
    expect(find.text('Aunt Wanjiru'), findsOneWidget);
    final debts = (await tester.runAsync(
      () => DriftDebtsRepository(db).debts(today: CalendarDate(2026, 10, 26)),
    ))!;
    expect(debts.single.isFormal, isFalse);
    expect(debts.single.balanceMinor, 2100000);

    await tester.tap(find.text('Aunt Wanjiru'));
    await settle(tester);
    await tester.tap(find.text('Record a payment'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount paid'),
      '1,000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await settle(tester);
    expect(find.text('20,000'), findsNWidgets(2));
  });

  testAppWidgets('lent money can be added and deleted', (tester) async {
    final db = openTestDatabase();
    await pumpGoals(tester, db: db, location: AppRoutes.lending);

    await tester.tap(find.text('Add'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Lent to'),
      'John',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1,500',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);
    expect(find.text('You lent'), findsOneWidget);
    expect(find.text('1,500'), findsNWidgets(2));

    await tester.tap(find.text('John'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await settle(tester);
    expect(find.text('John'), findsNothing);
    expect(await tester.runAsync(DriftLendingRepository(db).lent), isEmpty);
  });
}
