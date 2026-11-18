import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart' hide Tag;
import 'package:pesaclarity/src/features/ask/presentation/ask_entry.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/shared/widgets/marks.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

import '../../helpers/test_app.dart';
import 'balances_harness.dart';

void main() {
  late AppDatabase db;
  late ScenarioAccounts ids;

  setUp(() async {
    db = openTestDatabase();
    ids = await seedScenario(db);
  });

  Future<List<TransactionRecord>> rows(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.transactions).get()))!;

  testAppWidgets('Home: below zero once Fuliza is counted, so 0 is safe', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.home);
    expect(find.text('KES 0'), findsOneWidget);
    expect(
      find.textContaining("You're below zero once Fuliza is counted"),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home-on-hand')),
        matching: find.text('-1,150'),
      ),
      findsOneWidget,
    );
    // M-Pesa's counted-twice payment shows as a line under the card.
    expect(find.byKey(const Key('home-balance-warning')), findsOneWidget);
    expect(find.text("M-Pesa doesn't add up"), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-on-hand')));
    await settle(tester);
    expect(find.text('On hand: -KES 1,150'), findsOneWidget);
    expect(find.text('Example Sacco'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(Key('on-hand-account-${ids.mpesa}')),
        matching: find.text('-1,300'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Includes 1,300 Fuliza owed'), findsOneWidget);
  });

  testAppWidgets('Balances lists accounts, savings apart, with badges', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.balances);
    expect(find.text('DAY TO DAY'), findsOneWidget);
    expect(find.text('SAVINGS'), findsOneWidget);
    expect(find.text('1,200 short'), findsOneWidget);
    expect(
      find.text('1 matches · 1 needs a look · 2 have no messages'),
      findsOneWidget,
    );
    // Cash and the SACCO report no balance: the same neutral chip the
    // summary counts, and no other word for it.
    expect(find.text('No messages'), findsNWidgets(2));
    for (final id in [ids.cash, ids.sacco]) {
      final tag = find.descendant(
        of: find.byKey(Key('balance-account-$id')),
        matching: find.byType(Tag),
      );
      expect(tester.widget<Tag>(tag).text, 'No messages');
      expect(tester.widget<Tag>(tag).tone, Tone.info);
    }
    expect(find.text('Count again'), findsNothing);
    expect(find.text('Not reported'), findsNothing);
    expect(find.textContaining('1,300 Fuliza owed'), findsOneWidget);
    // The total leaves savings out, as On hand does: -1,300 + 50 + 100.
    expect(find.text('-KES 1,150'), findsOneWidget);
    expect(find.text('KES 12,350'), findsNothing);
  });

  testAppWidgets('Balances: counting cash is still a tap away', (tester) async {
    await pumpBalances(tester, db, AppRoutes.balances);
    await tester.tap(find.byKey(Key('balance-account-${ids.cash}')));
    await settle(tester);
    expect(find.byKey(const Key('account-set-balance')), findsOneWidget);
  });

  testAppWidgets('Home: On hand below zero takes the danger colour', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pumpBalances(tester, db, AppRoutes.home, theme: theme);
      final colors = theme.extension<PesaColors>()!;
      final onHand = find.byKey(const Key('home-on-hand'));
      final figure = tester.widget<Text>(
        find.descendant(of: onHand, matching: find.text('-1,150')),
      );
      // Red text on the plain tile: brand red in light, brightened in dark
      // to read on a card (where brand red is 2.9:1); the red lead card
      // keeps its figure white.
      expect(figure.style!.color, theme.colorScheme.error);
      expect(
        figure.style!.color,
        theme.brightness == Brightness.dark
            ? colors.link
            : const Color(0xFFC8102E),
      );
      expect(
        tester.widget<Text>(find.text('KES 0')).style!.color,
        theme.colorScheme.onPrimary,
      );
      final card = tester.widget<Card>(
        find.descendant(of: onHand, matching: find.byType(Card)),
      );
      expect(card.color, isNull, reason: 'the plain theme card');
      // Runway is a length of time, not a figure below zero.
      expect(
        tester.widget<Text>(find.text('Today')).style!.color,
        theme.colorScheme.onSurface,
      );
    }
  });

  testAppWidgets('Home: the last card scrolls fully above the Ask bar', (
    tester,
  ) async {
    await pumpBalances(
      tester,
      db,
      AppRoutes.home,
      size: const Size(1000, 1800),
    );
    final bar = find.byKey(const Key('ask-bar'));
    final barHeight = tester.getSize(bar).height;
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await settle(tester);
    final barTop =
        tester.getBottomLeft(find.byType(AskBarScope)).dy -
        AskBarScope.margin.bottom -
        barHeight;
    expect(
      tester.getBottomLeft(find.byKey(const Key('home-coming-up'))).dy,
      lessThanOrEqualTo(barTop),
    );
  });

  testAppWidgets('Set the balance records a correction that can be undone', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.balances);
    await tester.tap(find.byKey(Key('balance-account-${ids.cash}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('account-set-balance')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('set-balance-amount')), '60');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('set-balance-correction')),
        matching: find.text('-40'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('set-balance-save')));
    await settle(tester);

    final correction = (await rows(tester))
        .singleWhere((r) => r.kind == TransactionKind.correction);
    expect(correction.accountId, ids.cash);
    expect(correction.amountMinor, 4000);
    expect(correction.direction, TransactionDirection.outflow);
    expect(correction.balanceAfterMinor, 6000);
    expect(find.text('60'), findsWidgets);

    await tester.tap(find.byKey(Key('balance-account-${ids.cash}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('account-undo-correction')));
    await settle(tester);
    expect(
      (await rows(tester)).where((r) => r.kind == TransactionKind.correction),
      isEmpty,
    );
  });

  testAppWidgets('M-Pesa set below zero owes Fuliza', (tester) async {
    await pumpBalances(tester, db, AppRoutes.balances);
    await tester.tap(find.byKey(Key('balance-account-${ids.mpesa}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('account-set-balance')));
    await settle(tester);
    await tester.tap(find.text('Owes Fuliza').last);
    await tester.enterText(find.byKey(const Key('set-balance-amount')), '1500');
    await tester.tap(find.byKey(const Key('set-balance-save')));
    await settle(tester);
    final correction = (await rows(tester))
        .singleWhere((r) => r.kind == TransactionKind.correction);
    expect(correction.balanceAfterMinor, -150000);
    expect(correction.amountMinor, 20000);
  });

  testAppWidgets('the balance check finds the copy and removes it', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.balanceCheck);
    expect(find.text('1 thing to fix'), findsOneWidget);
    expect(find.text('Counted twice'), findsOneWidget);
    await tester.tap(find.byKey(const Key('balance-check-fix-all')));
    await settle(tester);
    expect(find.text('Everything adds up'), findsOneWidget);
    expect(
      (await rows(tester))
          .where((r) => r.source == TransactionSource.statement),
      isEmpty,
    );
  });

  testAppWidgets('adds a cash account with what it holds', (tester) async {
    await pumpBalances(tester, db, AppRoutes.balances);
    await tester.scrollUntilVisible(
      find.byKey(const Key('balances-add-account')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('balances-add-account')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('add-account-name')), 'Wallet');
    await tester.enterText(find.byKey(const Key('add-account-balance')), '500');
    await tester.tap(find.byKey(const Key('add-account-save')));
    await settle(tester);
    final added = await tester.runAsync(
      () => (db.select(
        db.accounts,
      )..where((a) => a.name.equals('Wallet'))).getSingle(),
    );
    expect(added!.type, AccountType.cash);
    expect(added.openingBalanceMinor, 50000);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testAppWidgets('Check this message: My accounts matches the other side', (
    tester,
  ) async {
    final item = (await db.select(db.reviewItems).get()).first;
    await pumpBalances(tester, db, AppRoutes.reviewMessage(item.id));
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('review-kind')),
            matching: find.byType(Text),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('review-choice-myAccounts')).last);
    await settle(tester);
    expect(find.text('Save as a transfer'), findsOneWidget);
    // M-Pesa's side has not been checked yet, so it waits.
    expect(find.byKey(const Key('review-own-waiting')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-save-transfer')));
    await settle(tester);

    final saved = (await rows(tester))
        .singleWhere((r) => r.messageHash == item.messageHash);
    expect(saved.accountId, ids.kcb);
    expect(saved.transferAccountId, ids.mpesa);
    expect(saved.transferPairId, isNull);
  });

  testAppWidgets('Check this message: pairs at once when the side is here', (
    tester,
  ) async {
    final item = (await db.select(db.reviewItems).get()).first;
    final received = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: ids.mpesa,
            occurredAt: scenarioNow.subtract(const Duration(minutes: 56)),
            amountMinor: 200000,
            direction: TransactionDirection.inflow,
            kind: const Value(TransactionKind.received),
            source: TransactionSource.sms,
          ),
        );
    await pumpBalances(tester, db, AppRoutes.reviewMessage(item.id));
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('review-kind')),
            matching: find.byType(Text),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('review-choice-myAccounts')).last);
    await settle(tester);
    expect(find.text('Matched with M-Pesa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-save-transfer')));
    await settle(tester);
    final saved = (await rows(tester))
        .singleWhere((r) => r.messageHash == item.messageHash);
    expect(saved.transferPairId, received);
  });

  testAppWidgets('Activity shows a matched pair as one line, and unmatches', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.activity);
    expect(find.text('KCB → M-Pesa'), findsOneWidget);
    expect(find.text('Own transfer · not spending · fee 30'), findsOneWidget);
    await tester.tap(find.text('KCB → M-Pesa'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('own-transfer-unmatch')));
    await settle(tester);
    expect(
      (await rows(tester)).where((r) => r.transferPairId != null),
      isEmpty,
    );
    final declined = await tester.runAsync(
      () => db.select(db.declinedTransfers).get(),
    );
    expect(declined, hasLength(1));
    // Let the note's timer run out.
    await tester.pump(const Duration(seconds: 10));
  });

  testAppWidgets('Messages to check warns when a balance does not match', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.review);
    expect(
      find.byKey(Key('review-balance-warning-${ids.mpesa}')),
      findsOneWidget,
    );
  });

  testAppWidgets('Profile shows Balances and how many need a look', (
    tester,
  ) async {
    await pumpBalances(tester, db, AppRoutes.profile);
    expect(find.text('4 accounts · 1 needs a look'), findsOneWidget);
  });

  test('the seeded transfer pairs as soon as it is stored', () async {
    final paired = await (db.select(
      db.transactions,
    )..where((t) => t.transferPairId.isNotNull())).get();
    expect(paired, hasLength(2));
  });
}
