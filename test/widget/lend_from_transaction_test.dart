// "I lent this" and the other Lent and borrowed answers, from a
// transaction's category picker, and how Activity then names it.
// Synthetic names and numbers only.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/lending_repository.dart';
import 'package:pesaclarity/src/data/repositories/payees_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/payees/presentation/transaction_sheet.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// Wednesday 28 October 2026, 08:00 EAT.
DateTime _now() => DateTime.utc(2026, 10, 28, 5);

final _phone = PayeeIdentifier.phone('0700 000 004')!;

/// Money out (or in) to Test Grace on 26 October.
Future<int> _seed(AppDatabase db, {bool out = true}) async {
  final mpesa = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026, 9),
        ),
      );
  final grace = await DriftPayeesRepository(db)
      .name(_phone, displayName: 'Test Grace');
  return DriftTransactionsRepository(db).add(
    TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: DateTime.utc(2026, 10, 26, 9),
      amountMinor: 250000,
      direction: out
          ? TransactionDirection.outflow
          : TransactionDirection.inflow,
      kind: Value(out ? TransactionKind.sent : TransactionKind.received),
      source: TransactionSource.sms,
      payeeId: Value(grace),
      counterpartyKind: Value(_phone.kind),
      counterpartyValue: Value(_phone.value),
      receiptNo: const Value('TLD0000001'),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  Widget home, {
  Space space = Space.personal,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(_now),
        activeSpaceProvider.overrideWithValue(space),
        loadedCategoriserProvider.overrideWithValue(
          const AsyncData(
            LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled),
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

Widget _opener(int id) => Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () => showTransactionSheet(context, id),
      child: const Text('Open'),
    ),
  ),
);

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.text('Category'));
  await _settle(tester);
}

void main() {
  testAppWidgets('I lent this opens the loan sheet filled in, and Activity '
      'says who it was lent to', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => _seed(db));
    await _pump(tester, db, const ActivityScreen());

    // An uncategorised row opens its suggestion, or the picker itself.
    await tester.tap(find.text('Test Grace'));
    await _settle(tester);
    if (find.text('Change').evaluate().isNotEmpty) {
      await tester.tap(find.text('Change'));
      await _settle(tester);
    }
    expect(find.text('LENT AND BORROWED'), findsOneWidget);
    expect(find.text('Paid back a loan'), findsOneWidget);
    expect(find.text('A loan to me'), findsNothing);
    await tester.tap(find.text('I lent this'));
    await _settle(tester);

    // The loan sheet, as "I lent", from the payment.
    expect(find.text('Add a loan'), findsOneWidget);
    expect(find.text('I borrowed'), findsNothing);
    expect(
      tester.widget<TextField>(fieldLabelled('Lent to')).controller!.text,
      'Test Grace',
    );
    expect(
      tester.widget<TextField>(fieldLabelled('Amount')).controller!.text,
      '2,500',
    );
    expect(find.textContaining('26 Oct'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final loan = (await tester.runAsync(
      () => DriftLendingRepository(db).lent(),
    ))!.single;
    expect(loan.person, 'Test Grace');
    expect(loan.amountMinor, 250000);
    expect(loan.lentOn, CalendarDate(2026, 10, 26));
    // Activity names the loan, and so does the transaction's sheet.
    expect(findDetailLine('Lent to Test Grace · M-Pesa'), findsOneWidget);
    await tester.tap(find.text('Test Grace'));
    await _settle(tester);
    expect(find.text('Money lent · Lent to Test Grace'), findsOneWidget);
  });

  testAppWidgets('money in offers a loan to me and paying me back', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = (await tester.runAsync(() => _seed(db, out: false)))!;
    await _pump(tester, db, _opener(id));
    await tester.tap(find.text('Open'));
    await _settle(tester);
    await _openPicker(tester);
    expect(find.text('Paying me back'), findsOneWidget);
    expect(find.text('I lent this'), findsNothing);
    await tester.tap(find.text('A loan to me'));
    await _settle(tester);

    final debt = (await tester.runAsync(
      () => db.select(db.debts).getSingle(),
    ))!;
    expect(debt.lender, 'Test Grace');
    expect(debt.startingBalanceMinor, 250000);
    expect(find.textContaining('Borrowed from Test Grace'), findsOneWidget);

    // Another category takes it back out of Debts.
    await _openPicker(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Uncategorised').last);
    await _settle(tester);
    expect(await tester.runAsync(() => db.select(db.debts).get()), isEmpty);
  });

  testAppWidgets('a business keeps its own credit, so offers none of them', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = (await tester.runAsync(() => _seed(db)))!;
    await _pump(
      tester,
      db,
      _opener(id),
      space: const Space(
        id: 'shop1',
        name: 'Test Stall',
        kind: SpaceKind.business,
      ),
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    await _openPicker(tester);
    expect(find.text('Choose a category'), findsOneWidget);
    expect(find.text('LENT AND BORROWED'), findsNothing);
    expect(find.text('I lent this'), findsNothing);
  });
}
