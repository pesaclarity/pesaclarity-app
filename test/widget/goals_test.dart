import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../helpers/goals_harness.dart';
import '../helpers/test_app.dart';

void main() {
  Future<void> seed(AppDatabase db) async {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingBalanceMinor: const Value(5000000),
            openingDate: DateTime.utc(2026, 9),
          ),
        );
    final debts = DriftDebtsRepository(db);
    final bank = await debts.add(
      DebtsCompanion.insert(
        lender: 'Bank salary advance',
        type: DebtType.salaryAdvance,
        startingBalanceMinor: 10000000,
        annualRateBasisPoints: const Value(1300),
        minimumPaymentMinor: const Value(2000000),
      ),
    );
    await debts.confirmBalance(bank, 8230000, DateTime.utc(2026, 10));
    final family = await debts.add(
      DebtsCompanion.insert(
        lender: 'Family loan',
        type: DebtType.family,
        startingBalanceMinor: 2100000,
        isFormal: const Value(false),
      ),
    );
    await debts.setInstalments(family, [
      DebtInstalment(dueDate: CalendarDate(2027, 1, 31), amountMinor: 2100000),
    ]);
    final goals = DriftGoalsRepository(db);
    await goals.add(
      name: 'Emergency fund',
      targetMinor: 15000000,
      savedMinor: 6000000,
      targetDate: CalendarDate(2026, 12, 31),
    );
    await goals.add(name: 'New laptop', targetMinor: 30000000);
  }

  testAppWidgets('shows debt progress, goals and net worth', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seed(db));
    await pumpGoals(tester, db: db);

    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.text('103,300 left · 0 of 2 cleared'), findsOneWidget);
    expect(find.text('Bank salary advance'), findsOneWidget);
    expect(find.text('82,300'), findsOneWidget);
    expect(find.textContaining('13% p.a. · cleared'), findsOneWidget);
    expect(find.text('Interest-free · in full, 31 Jan 2027'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('New laptop'), 200);
    expect(find.text('60,000 of 150,000'), findsOneWidget);
    expect(find.text('30,000 a month to Dec 2026'), findsOneWidget);
    expect(find.text('0 of 300,000'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Lent and borrowed'), 200);
    expect(find.text('Net worth'), findsOneWidget);
    // 50,000 in M-Pesa less 82,300 and 21,000 owed.
    expect(find.text('-53,300'), findsOneWidget);
    expect(find.text('Owed to you 0 · you owe 21,000'), findsOneWidget);
  });

  testAppWidgets('adds, edits and deletes a goal', (tester) async {
    final db = openTestDatabase();
    await pumpGoals(tester, db: db);

    expect(find.text('Add a debt'), findsWidgets);
    expect(find.text('Debt-free'), findsNothing);
    await tester.tap(find.text('Add a goal').first);
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What are you saving for?'),
      'School fees',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Target'),
      '45,000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Saved so far'),
      '15000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
    await settle(tester);

    expect(find.text('School fees'), findsOneWidget);
    expect(find.text('15,000 of 45,000'), findsOneWidget);

    await tester.tap(find.text('School fees'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Saved so far'),
      '45,000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.text('Reached'), findsOneWidget);

    await tester.tap(find.text('School fees'));
    await settle(tester);
    await tester.tap(find.text('Delete goal'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('School fees'), findsNothing);
    expect(
      await tester.runAsync(() => DriftGoalsRepository(db).goals()),
      isEmpty,
    );
  });

  testAppWidgets('a goal needs a name and a target', (tester) async {
    await pumpGoals(tester, db: openTestDatabase());
    await tester.tap(find.text('Add a goal').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add goal'));
    await settle(tester);
    expect(find.text('Give the goal a name.'), findsOneWidget);
    expect(find.text('Enter an amount above 0.'), findsOneWidget);
  });

  testAppWidgets('debts open the Debts screen', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => seed(db));
    await pumpGoals(tester, db: db);
    await tester.tap(find.text('Family loan'));
    await settle(tester);
    expect(find.text('Debts screen'), findsOneWidget);
  });
}
