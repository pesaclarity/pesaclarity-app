import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/data/repositories/savings_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/presentation/choose_accounts_screen.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/savings/presentation/savings_account_screen.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';
import '../screenshots/savings_records.dart';

// A made-up saver (savings_records.dart): payments to Chumz's public
// paybill under the invented codes CH12345 and CH67890.

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  Widget home, {
  String space = personalSpaceId,
}) async {
  // Tall enough that every row is built.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        personalDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => savingsNow),
        pdfTextExtractorProvider.overrideWithValue(null),
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(space)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

Future<SavingsSeeded> _seed(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => SavingsRecords(db).seed()))!;

Future<int> _added(
  WidgetTester tester,
  AppDatabase db, {
  bool balances = true,
}) async => (await tester.runAsync(() async {
  final records = SavingsRecords(db);
  return records.addChumz(await records.seed(), balances: balances);
}))!;

void main() {
  testAppWidgets('Activity asks under the payment, and adding links them', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _seed(tester, db);
    await _pump(tester, db, const ActivityScreen());

    expect(find.text('Is this your Chumz savings?'), findsOneWidget);
    expect(
      find.text(
        'You paid NABO CAPITAL LTD, which runs Chumz. Add it as a savings '
        'account so payments count as saving, not spending.',
      ),
      findsOneWidget,
    );
    expect(find.text('M-Pesa → Chumz'), findsNothing);

    await tester.tap(find.byKey(const Key('savings-prompt-add')));
    await _settle(tester);
    expect(find.text('Add Chumz'), findsWidgets);
    expect(find.text('M-Pesa paybill NABO CAPITAL LTD'), findsOneWidget);
    expect(find.text('Nabo Capital'), findsOneWidget);
    expect(find.textContaining('CH12345', findRichText: true), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('add-savings-goal-name-CH12345')),
      'Christmas',
    );
    await tester.enterText(
      find.byKey(const Key('add-savings-goal-name-CH67890')),
      'School fees',
    );
    await tester.ensureVisible(find.byKey(const Key('add-savings')));
    await tester.tap(find.byKey(const Key('add-savings')));
    await _settle(tester);

    // The question is gone; payments are own transfers, told once.
    expect(find.text('Is this your Chumz savings?'), findsNothing);
    expect(find.text('M-Pesa → Chumz'), findsWidgets);
    expect(find.text('Chumz → M-Pesa'), findsOneWidget);
    expect(find.text('Chumz added · 4 older payments updated'), findsOneWidget);
    final pockets = await tester.runAsync(
      () => db.select(db.savingsPockets).get(),
    );
    expect(pockets!.map((p) => p.name), ['Christmas', 'School fees']);
  });

  testAppWidgets("It's not mine stops the question; it can be added later", (
    tester,
  ) async {
    final db = openTestDatabase();
    await _seed(tester, db);
    await _pump(tester, db, const ActivityScreen());

    await tester.tap(find.byKey(const Key('savings-prompt-decline')));
    await _settle(tester);
    expect(find.text('Is this your Chumz savings?'), findsNothing);
    expect(find.text('M-Pesa → Chumz'), findsNothing);
    expect(await tester.runAsync(() => DriftSavingsRepository(db).declined()), {
      'chumz',
    });

    await _pump(tester, db, const ChooseAccountsScreen());
    await scrollTo(tester, find.byKey(const Key('savings-add-chumz')));
    expect(find.text('Chumz · Nabo Capital'), findsOneWidget);
    await tester.tap(find.byTooltip('Add Chumz'));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('add-savings')));
    await tester.tap(find.byKey(const Key('add-savings')));
    await _settle(tester);
    expect(find.byKey(const Key('savings-add')), findsNothing);
    final accounts = await tester.runAsync(
      () => DriftSavingsRepository(db).accounts(),
    );
    expect(accounts!.single.pockets.map((p) => p.name), ['CH12345', 'CH67890']);
  });

  testAppWidgets('My accounts lists Chumz in its own card and opens it', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _added(tester, db);
    await _pump(tester, db, const MyAccountsSettingsScreen());

    expect(find.text('SAVINGS APPS'), findsOneWidget);
    expect(find.text('Chumz · Nabo Capital'), findsOneWidget);
    expect(find.text('2 goals · 1 locked'), findsOneWidget);
    expect(
      find.text('Outside M-Pesa · you pay in from M-Pesa'),
      findsOneWidget,
    );
    // Not in the plain list as well.
    expect(find.text('Chumz'), findsNothing);

    await tester.tap(find.text('Chumz · Nabo Capital'));
    await _settle(tester);
    expect(find.text('KES 4,700'), findsOneWidget);
    expect(
      find.text('Held by Nabo Capital · paid in from M-Pesa'),
      findsOneWidget,
    );
    expect(find.text('Set by you · 21 Nov'), findsOneWidget);
    expect(find.text('5,615'), findsOneWidget);
    expect(find.text('+85'), findsWidgets);
    expect(find.text('Locked until 15 Dec · CH12345'), findsOneWidget);
    expect(find.text('Open · CH67890'), findsOneWidget);
    expect(find.text('Includes 85 interest · Sat 21 Nov'), findsOneWidget);
    expect(find.text('From M-Pesa · Christmas'), findsWidgets);
  });

  testAppWidgets('Update balance asks which goal a withdrawal was from', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = await _added(tester, db, balances: false);
    // The money back went to the one goal open that day; take it out of
    // it, as for money back when no goal is open.
    await tester.runAsync(() async {
      final savings = DriftSavingsRepository(db);
      final account = await savings.account(id);
      final back = account!.entries.firstWhere((e) => !e.isPaidIn);
      await savings.assignEntry(back.transactionId, null);
      await savings.dispose();
    });
    await _pump(tester, db, SavingsAccountScreen(accountId: id));
    expect(find.text('From your payments so far'), findsOneWidget);

    await tester.tap(find.byKey(const Key('savings-update-balance')));
    await _settle(tester);
    expect(find.text('WHICH GOAL WAS IT FROM?'), findsOneWidget);
    final account = await tester.runAsync(
      () => DriftSavingsRepository(db).account(id),
    );
    final christmas = account!.pockets.first;
    final school = account.pockets.last;
    await tester.enterText(
      find.descendant(
        of: find.byKey(Key('savings-balance-${christmas.id}')),
        matching: find.byType(TextField),
      ),
      '3,200',
    );
    await tester.ensureVisible(find.byKey(const Key('savings-update-save')));
    await tester.tap(find.byKey(const Key('savings-update-save')));
    await _settle(tester);
    expect(find.text('Choose a goal for each withdrawal.'), findsOneWidget);

    final withdrawal = account.unassigned.single;
    await tester.ensureVisible(
      find.byKey(Key('savings-assign-${withdrawal.transactionId}')),
    );
    await tester.tap(
      find.byKey(Key('savings-assign-${withdrawal.transactionId}')),
    );
    await _settle(tester);
    await tester.tap(find.text('School fees').last);
    await _settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(Key('savings-balance-${school.id}')),
        matching: find.byType(TextField),
      ),
      '1,500',
    );
    await tester.ensureVisible(find.byKey(const Key('savings-update-save')));
    await tester.tap(find.byKey(const Key('savings-update-save')));
    await _settle(tester);

    expect(find.text('KES 4,700'), findsOneWidget);
    expect(find.text('Interest so far'), findsOneWidget);
    expect(find.text('Includes 85 interest · Sat 21 Nov'), findsOneWidget);
  });

  testAppWidgets('a goal is renamed and locked from its sheet', (tester) async {
    final db = openTestDatabase();
    final id = await _added(tester, db);
    await _pump(tester, db, SavingsAccountScreen(accountId: id));
    await tester.tap(find.text('Open · CH67890'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('savings-pocket-name')),
      'Fees 2027',
    );
    await tester.tap(find.byKey(const Key('savings-pocket-save')));
    await _settle(tester);
    expect(find.text('Fees 2027'), findsOneWidget);
  });

  testAppWidgets('Remove Chumz puts the payments back, after asking', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = await _added(tester, db);
    await _pump(tester, db, SavingsAccountScreen(accountId: id));
    await scrollTo(tester, find.byKey(const Key('savings-remove')));
    await tester.tap(find.byKey(const Key('savings-remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Chumz?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    expect(
      await tester.runAsync(() => DriftSavingsRepository(db).accounts()),
      isEmpty,
    );
    expect(await tester.runAsync(() => DriftSavingsRepository(db).declined()), {
      'chumz',
    });
  });

  testAppWidgets('a goal saved in Chumz shows where and until when', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _added(tester, db);
    await _pump(tester, db, const GoalsScreen());
    expect(find.text('Saved in Chumz'), findsNWidgets(2));
    expect(find.text('Locked until 15 Dec'), findsOneWidget);
    expect(find.text('3,200 of 10,000'), findsOneWidget);

    // Its sheet chooses where it is saved and hides "Saved so far".
    await tester.tap(find.text('Christmas'));
    await _settle(tester);
    expect(find.text('Saved so far'), findsNothing);
    expect(find.text('Chumz · Christmas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('goal-saved-in')));
    await _settle(tester);
    await tester.tap(find.text('Nowhere, I type it').last);
    await _settle(tester);
    expect(find.text('Saved so far'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    final goals = await tester.runAsync(() => DriftGoalsRepository(db).goals());
    expect(goals!.firstWhere((g) => g.name == 'Christmas').backing, isNull);
  });

  testAppWidgets('a payment into Chumz offers no Unmatch, only its page', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _added(tester, db);
    await _pump(tester, db, const ActivityScreen());
    await tester.tap(find.text('M-Pesa → Chumz').first);
    await _settle(tester);
    expect(find.byKey(const Key('own-transfer-unmatch')), findsNothing);
    await tester.tap(find.byKey(const Key('own-transfer-savings')));
    await _settle(tester);
    expect(find.text('KES 4,700'), findsOneWidget);
  });

  testAppWidgets('only Personal is asked about Chumz', (tester) async {
    final db = openTestDatabase();
    await _seed(tester, db);
    await _pump(tester, db, const ActivityScreen(), space: 'shop1');
    expect(find.text('Is this your Chumz savings?'), findsNothing);
    expect(find.text('NABO CAPITAL LTD C2B'), findsWidgets);
  });
}
