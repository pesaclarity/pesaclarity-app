// Fuliza is optional: it shows only for people who use it, and they can
// stop tracking it. Made-up records (balances_harness.dart).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart'
    hide BudgetItem, Tag;
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/fuliza_tracking.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/plan_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/context.dart';
import 'package:pesaclarity/src/domain/ask/reply_writer.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/activity/application/activity_providers.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/debts/application/debts_overview_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';
import 'balances_harness.dart';

String _filled(AskAnswer a) => fillTemplate(
  a.template,
  a.facts,
  money: (minor) => moneyOrHidden(minor, hidden: false, withCurrency: false),
);

/// Removes the scenario's Fuliza draw: its payment still took M-Pesa to 0,
/// so the books still work out Fuliza from the balances, but no Fuliza
/// message was read.
Future<void> _withoutFulizaMessages(AppDatabase db) => (db.delete(
  db.transactions,
)..where((t) => t.kind.equalsValue(TransactionKind.fulizaDraw))).go();

/// The scenario's Fuliza draw, as its message is read.
Future<void> _readFulizaDraw(AppDatabase db, int mpesa) =>
    DriftTransactionsRepository(db).addNew([
      TransactionsCompanion.insert(
        accountId: mpesa,
        occurredAt: eat(2026, 11, 13, 18, 40).add(const Duration(seconds: 20)),
        amountMinor: 128713,
        direction: TransactionDirection.inflow,
        kind: const Value(TransactionKind.fulizaDraw),
        feeMinor: const Value(1287),
        source: TransactionSource.sms,
        dedupeKey: const Value('late-fuliza'),
        receiptNo: const Value('TST0000777'),
        owedAfterMinor: Value(kes(1300)),
      ),
    ]);

void main() {
  late AppDatabase db;
  late ScenarioAccounts ids;

  setUp(() async {
    db = openTestDatabase();
    ids = await seedScenario(db);
  });

  group('the books and figures', () {
    late ProviderContainer c;

    setUp(() {
      c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => scenarioNow),
          askReaderRuntimeOpenerProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);
    });

    Future<void> track(bool on) async {
      await c.read(fulizaTrackedProvider.notifier).setTracked(on);
    }

    Future<String> ask(String question) async {
      final engine = await c.read(askEngineProvider.future);
      final turn = await engine.ask(
        question,
        context: AskContext.empty,
        now: scenarioNow,
      );
      return _filled(turn.answer);
    }

    /// What every figure the switch must not change reads now.
    Future<Map<String, Object?>> figures() async {
      final journal = await c.read(journalRepositoryProvider).read();
      final week = weekInOut(
        await c.read(activityEntriesProvider(CalendarDate(2026, 11, 1)).future),
        today: CalendarDate.local(scenarioNow),
      );
      final overview = await c.read(balancesOverviewProvider.future);
      return {
        'wallet': overview.byId(ids.mpesa)!.walletMinor,
        'kcb': overview.byId(ids.kcb)!.heldMinor,
        'in': week.inMinor,
        'out': week.outMinor,
        'not yet sorted': journal.balanceOf(
          BookAccount.notYetSorted,
          currency: 'KES',
        ),
        'charges': journal.balanceOf(
          BookAccount.fulizaCharges,
          currency: 'KES',
        ),
      };
    }

    test(
      'no Fuliza message: no Fuliza owed anywhere, not in Ask either; M-Pesa '
      'is the balance M-Pesa reported',
      () async {
        await _withoutFulizaMessages(db);
        expect(
          await c.read(fulizaTrackingProvider.future),
          FulizaTracking.unseen,
        );

        final overview = await c.read(balancesOverviewProvider.future);
        final mpesa = overview.byId(ids.mpesa)!;
        // The books still work Fuliza out from the balances; none of it shows.
        expect(mpesa.walletMinor, 0);
        expect(mpesa.fulizaOwedMinor, 0);
        expect(mpesa.heldMinor, 0);
        // 0 + 50 + 100.
        expect(overview.totalMinor('KES'), kes(150));
        final onHand = (await c.read(onHandProvider.future))!;
        expect(onHand.fulizaOwedMinor, 0);
        expect(onHand.totalMinor, kes(150));
        final debts = await c.read(debtsOverviewProvider.future);
        expect(debts.fulizaDebt, isNull);
        expect(debts.fuliza, isNull);
        expect(debts.fulizaShown, isFalse);
        expect(await c.read(fulizaAutoProvider.future), isEmpty);

        for (final question in [
          "what's my M-Pesa balance",
          'How much money do I have?',
          'How much did I pay in charges this month?',
          'How much came in this month?',
        ]) {
          expect(
            await ask(question),
            isNot(contains(RegExp('fuliza', caseSensitive: false))),
            reason: question,
          );
        }
      },
    );

    test('Fuliza shows with the first Fuliza message, as before', () async {
      await _withoutFulizaMessages(db);
      expect((await c.read(fulizaTrackingProvider.future)).shown, isFalse);

      await _readFulizaDraw(db, ids.mpesa);
      // As the ledger's change does in the app.
      c
        ..invalidate(ledgerChangesProvider)
        ..invalidate(fulizaTrackingProvider)
        ..invalidate(balancesOverviewProvider);
      expect(
        await c.read(fulizaTrackingProvider.future),
        const FulizaTracking(seen: true, tracked: true),
      );
      final mpesa = (await c.read(balancesOverviewProvider.future))
          .byId(ids.mpesa)!;
      expect(mpesa.fulizaOwedMinor, kes(1300));
      expect(mpesa.heldMinor, kes(-1300));
      expect(
        await ask("what's my M-Pesa balance"),
        "M-Pesa is 1,300 below zero: that's what you owe Fuliza.",
      );
    });

    test(
      'off hides Fuliza and keeps every figure; on brings it all back',
      () async {
        // Safe to spend needs a day-to-day budget.
        final daily = await (db.select(
          db.categories,
        )..where((t) => t.isDailySpending.equals(true))).get();
        if (daily.isNotEmpty) {
          await c
              .read(planRepositoryProvider)
              .saveBudgetItem(
                BudgetItem(
                  month: CalendarDate.local(scenarioNow).yearMonth,
                  name: 'Food',
                  amountMinor: kes(9000),
                  kind: BudgetItemKind.oneOff,
                  categoryId: daily.first.id,
                ),
              );
        }
        final before = await figures();
        expect((await c.read(fulizaTrackingProvider.future)).shown, isTrue);
        final safeOn = await c.read(safeToSpendTodayProvider.future);

        await track(false);
        expect(
          await c.read(fulizaTrackingProvider.future),
          const FulizaTracking(seen: true, tracked: false),
        );
        // The books are as they were: every wallet, In and Out, Not yet
        // sorted and the charges.
        expect(await figures(), before);
        final overview = await c.read(balancesOverviewProvider.future);
        final mpesa = overview.byId(ids.mpesa)!;
        expect(mpesa.fulizaOwedMinor, 0);
        // M-Pesa at the balance M-Pesa reported: 0, not -1,300.
        expect(mpesa.heldMinor, 0);
        expect(overview.totalMinor('KES'), kes(150));
        expect((await c.read(onHandProvider.future))!.totalMinor, kes(150));
        final debts = await c.read(debtsOverviewProvider.future);
        expect(debts.fulizaDebt, isNull);
        expect(debts.fuliza, isNull);
        expect(await c.read(fulizaAutoProvider.future), isEmpty);
        if (daily.isNotEmpty) {
          final safeOff = (await c.read(safeToSpendTodayProvider.future))!;
          // On, M-Pesa is below zero once Fuliza counts, so nothing is safe;
          // off, the money on hand is the 150 the accounts report.
          expect(safeOn!.onHandMinor, kes(-1150));
          expect(safeOff.onHandMinor, kes(150));
        }
        final text = await ask("what's my M-Pesa balance");
        expect(text, isNot(contains('Fuliza')));

        await track(true);
        expect(await figures(), before);
        final back = (await c.read(balancesOverviewProvider.future))
            .byId(ids.mpesa)!;
        expect(back.fulizaOwedMinor, kes(1300));
        expect(back.heldMinor, kes(-1300));
        expect(
          (await c.read(debtsOverviewProvider.future)).fulizaDebt?.owedMinor,
          kes(1300),
        );
        expect(
          await ask("what's my M-Pesa balance"),
          "M-Pesa is 1,300 below zero: that's what you owe Fuliza.",
        );
      },
    );

    test('the switch is kept with the space that reads M-Pesa', () async {
      await track(false);
      expect(await fulizaTrackedIn(DriftAppSettingsRepository(db)), isFalse);
      expect((await readFulizaTracking(db)).shown, isFalse);
    });
  });

  group('the screens', () {
    Future<void> pumpMyAccounts(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            personalDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(() => scenarioNow),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const MyAccountsSettingsScreen(),
          ),
        ),
      );
      await settle(tester);
    }

    testAppWidgets('My accounts: no Track Fuliza before a Fuliza message', (
      tester,
    ) async {
      await tester.runAsync(() => _withoutFulizaMessages(db));
      await pumpMyAccounts(tester);
      expect(find.byKey(const Key('choose-accounts')), findsOneWidget);
      expect(find.byKey(const Key('track-fuliza')), findsNothing);
      expect(find.textContaining('Fuliza'), findsNothing);
    });

    testAppWidgets('My accounts: Track Fuliza, on by default, switches off '
        'and on again', (tester) async {
      await pumpMyAccounts(tester);
      final row = find.byKey(const Key('track-fuliza'));
      expect(tester.widget<SwitchListTile>(row).value, isTrue);
      await tester.tap(row);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(row).value, isFalse);
      expect(
        await tester.runAsync(
          () => fulizaTrackedIn(DriftAppSettingsRepository(db)),
        ),
        isFalse,
      );
      await tester.tap(row);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(row).value, isTrue);
    });

    testAppWidgets('no Fuliza message: Home and Balances never say Fuliza', (
      tester,
    ) async {
      await tester.runAsync(() => _withoutFulizaMessages(db));
      await pumpBalances(tester, db, AppRoutes.home);
      expect(find.textContaining('Fuliza'), findsNothing);
      await pumpBalances(tester, db, AppRoutes.balances);
      expect(find.textContaining('Fuliza'), findsNothing);
      expect(find.text('KES 150'), findsOneWidget);
    });

    testAppWidgets('off: Home, Balances and Activity leave Fuliza out', (
      tester,
    ) async {
      await tester.runAsync(
        () =>
            DriftAppSettingsRepository(db)
                .writeJson(trackFulizaKey, {'track': false}),
      );
      await pumpBalances(tester, db, AppRoutes.home);
      expect(find.textContaining('Fuliza'), findsNothing);
      await pumpBalances(tester, db, AppRoutes.balances);
      expect(find.textContaining('Fuliza'), findsNothing);
      expect(find.text('KES 150'), findsOneWidget);
      await pumpBalances(tester, db, AppRoutes.activity);
      expect(find.textContaining('Fuliza'), findsNothing);
    });
  });
}
