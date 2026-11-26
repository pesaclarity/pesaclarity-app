// The new pieces of the rest of decision 0027, as the approved screens show
// them: Put money in on More ways to record and its sheet, "Where it lands"
// on Pay yourself by bank, the restore check's card and sheet, and the
// question on Clear data. Made-up records only.
import 'package:drift/drift.dart' show StringExpressionOperators, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/database/space_databases.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/restore_check.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/home/presentation/add_menu.dart';
import 'package:pesaclarity/src/features/sales/presentation/records_sheets.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/manage_spaces_screens.dart';
import 'package:pesaclarity/src/features/spaces/presentation/restore_check_card.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/spaces_harness.dart';
import '../helpers/test_app.dart';

final _now = eat(2026, 11, 21, 9, 41);

const _stall = Space(
  id: 'stall',
  name: 'Vegetable stall',
  kind: SpaceKind.business,
);

/// Personal's M-Pesa and Equity bank; Grace Wambui's KES 650 switched to
/// the stall, which also has its cash drawer and KCB.
Future<void> _seed(AppDatabase personal, AppDatabase business) async {
  await DriftAppSettingsRepository(personal).writeJson(
    SpacesController.settingsKey,
    spacesToJson([Space.personal, _stall]),
  );
  final mpesa = await personal
      .into(personal.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingBalanceMinor: const Value(3781900),
          openingDate: eat(2026, 11, 1),
          institutionId: const Value('mpesa'),
        ),
      );
  await personal
      .into(personal.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Equity bank',
          type: AccountType.bank,
          openingBalanceMinor: const Value(2000000),
          openingDate: eat(2026, 11, 1),
        ),
      );
  for (final (name, type, minor) in [
    ('Cash', AccountType.cash, 200000),
    ('KCB', AccountType.bank, 1000000),
  ]) {
    await business
        .into(business.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingBalanceMinor: Value(minor),
            openingDate: eat(2026, 11, 1),
          ),
        );
  }
  final sale = await personal
      .into(personal.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: eat(2026, 11, 18, 17, 6),
          amountMinor: 65000,
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyName: const Value('GRACE WAMBUI'),
          receiptNo: const Value('SKL4AB12CD'),
          dedupeKey: const Value('SKL4AB12CD|65000'),
          balanceAfterMinor: const Value(3846900),
        ),
      );
  await DriftSpaceMoveRepository(
    personal,
    (_) async => (business, false),
    nameOf: (id) async => id == _stall.id ? _stall.name : 'Personal',
  ).move(sale, _stall.id);
}

typedef _Dbs = ({AppDatabase personal, AppDatabase business});

Future<_Dbs> _pump(
  WidgetTester tester, {
  Widget? screen,
  void Function(BuildContext context)? open,
  bool inStall = true,
  Future<void> Function(_Dbs dbs)? before,
}) async {
  final personal = openTestDatabase();
  final business = openTestDatabase();
  final dbs = (personal: personal, business: business);
  await tester.runAsync(() async {
    await business.becomeSpace(SpaceKind.business);
    await _seed(personal, business);
    await before?.call(dbs);
  });
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(inStall ? business : personal),
      personalDatabaseProvider.overrideWithValue(personal),
      mainDatabaseProvider.overrideWithValue(personal),
      clockProvider.overrideWithValue(() => _now),
      deviceRegionProvider.overrideWithValue('KE'),
      statementImportAvailableProvider.overrideWithValue(true),
      activeSpaceProvider.overrideWithValue(inStall ? _stall : Space.personal),
      activeSpaceIdProvider.overrideWith(
        () => ActiveSpaceId(inStall ? _stall.id : personalSpaceId),
      ),
      spaceDatabasesProvider.overrideWith(
        (ref) => TwoSpaceDatabases(ref, personal, business),
      ),
      ...appLockOverrides(),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light,
        home:
            screen ??
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => open!(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
      ),
    ),
  );
  await _settle(tester);
  if (screen == null) {
    await tester.tap(find.text('Open'));
    await _settle(tester);
  }
  return dbs;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _choose(WidgetTester tester, Key menu, Key item) async {
  await tester.ensureVisible(find.byKey(menu));
  await tester.tap(find.byKey(menu));
  await _settle(tester);
  await tester.tap(find.byKey(item).last);
  await _settle(tester);
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('Put money in', () {
    testWidgets('More ways to record has it under Pay yourself', (
      tester,
    ) async {
      await _pump(tester, open: (c) => showAddMenu(c, business: true));
      expect(find.text('Put money in'), findsOneWidget);
      expect(find.text('Your own money into the business'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Put money in')).dy,
        greaterThan(tester.getTopLeft(find.text('Pay yourself')).dy),
      );
      await _done(tester);
    });

    testWidgets('from your M-Pesa, staying on it: no money moves, and what '
        'it does in each space', (tester) async {
      final dbs = await _pump(tester, open: showPutMoneyInSheet);
      expect(
        find.text(
          'Your own money into the business. It is not a sale and not '
          'income.',
        ),
        findsOneWidget,
      );
      expect(find.text('Into Vegetable stall'), findsWidgets);
      expect(find.text('Stays on your M-Pesa'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('put-in-amount')), '3000');
      await _settle(tester);
      expect(
        find.text(
          "No money moves. KES 3,000 of your M-Pesa becomes the stall's.",
        ),
        findsOneWidget,
      );
      expect(find.text('Your own part of M-Pesa'), findsOneWidget);
      expect(find.text('Put in by you'), findsOneWidget);
      expect(find.text('-3,000'), findsOneWidget);
      expect(find.text('+3,000'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('put-in-save')));
      await tester.tap(find.byKey(const Key('put-in-save')));
      await _settle(tester);
      final rows = await tester.runAsync(
        () => (dbs.business.select(
          dbs.business.transactions,
        )..where((t) => t.linkId.like('putin:%'))).get(),
      );
      expect(rows, hasLength(1));
      await _done(tester);
    });

    testWidgets('from Equity bank: into Business bank, each side matching its '
        'own message', (tester) async {
      await _pump(tester, open: showPutMoneyInSheet);
      final menu = find.byKey(const Key('put-in-from-menu'));
      await tester.tap(menu);
      await _settle(tester);
      expect(find.text('Your cash'), findsWidgets);
      await tester.tap(find.text('Equity bank').last);
      await _settle(tester);
      expect(find.text('Stays on your M-Pesa'), findsNothing);
      await _choose(
        tester,
        const Key('put-in-into-menu'),
        const Key('put-in-into-businessBank'),
      );
      expect(
        find.text(
          'Send it yourself. It will match the Equity message in Personal '
          'and the KCB message here when they come.',
        ),
        findsOneWidget,
      );
      expect(find.text('KCB. Put in by you'), findsOneWidget);
      await _done(tester);
    });
  });

  group('Pay yourself by bank', () {
    testWidgets('"Where it lands" shows only from Business bank, with the '
        'note that Personal counts it once', (tester) async {
      await _pump(tester, open: showPayYourselfSheet);
      expect(find.text('Where it lands'), findsNothing);
      await _choose(
        tester,
        const Key('pay-yourself-from-menu'),
        const Key('pay-yourself-from-bank'),
      );
      expect(find.text('Where it lands'), findsOneWidget);
      expect(find.text('Your M-Pesa'), findsOneWidget);
      expect(
        find.text(
          'It will match the KCB message here and the M-Pesa message in '
          'Personal. Personal counts it once.',
        ),
        findsOneWidget,
      );
      await _choose(
        tester,
        const Key('pay-yourself-lands-menu'),
        const Key('pay-yourself-lands-untracked'),
      );
      expect(
        find.text(
          'It will match the KCB message here. Personal counts the pay, and '
          'none of your accounts there goes up.',
        ),
        findsOneWidget,
      );
      await _done(tester);
    });
  });

  group('restore check', () {
    Future<void> stallRestored(_Dbs dbs) async {
      await dbs.business.delete(dbs.business.transactions).go();
      await RestoreCheck.mark(() => dbs.business, eat(2026, 11, 14));
    }

    testWidgets('the card on Today, and the sheet with three answers', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const Scaffold(body: SafeArea(child: RestoreCheckCard())),
        before: stallRestored,
      );
      expect(find.text('1 payment on one side only'), findsOneWidget);
      expect(
        find.text('After the restore · Your M-Pesa still has them'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('restore-check-card')));
      await _settle(tester);
      expect(
        find.text(
          'Vegetable stall was restored from a backup of Sat 14 Nov. Your '
          "M-Pesa in Personal still holds these as the stall's.",
        ),
        findsOneWidget,
      );
      expect(find.text('Money in'), findsOneWidget);
      expect(find.textContaining('SKL4AB12CD'), findsOneWidget);
      expect(find.text('Make them again'), findsOneWidget);
      await tester.tap(find.byKey(const Key('restore-check-answer')));
      await _settle(tester);
      expect(find.text('They were mine'), findsOneWidget);
      await tester.tap(find.byKey(const Key('restore-check-leaveApart')).last);
      await _settle(tester);
      expect(
        find.text(
          "Nothing changes. Personal keeps KES 650 as the stall's, and the "
          'stall does not show these.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('restore-check-go')));
      await _settle(tester);
      expect(find.text('1 payment on one side only'), findsNothing);
      await _done(tester);
    });

    testWidgets('Personal restored: two answers, made again in Personal', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const Scaffold(body: SafeArea(child: RestoreCheckCard())),
        inStall: false,
        before: (dbs) async {
          await dbs.personal.delete(dbs.personal.balanceRecords).go();
          await RestoreCheck.mark(() => dbs.personal, eat(2026, 11, 14));
        },
      );
      expect(
        find.text('After the restore · Vegetable stall still has them'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('restore-check-card')));
      await _settle(tester);
      expect(find.text('Sales · GRACE WAMBUI'), findsOneWidget);
      expect(find.text('Make them again in Personal'), findsOneWidget);
      expect(
        find.text(
          "They count in your M-Pesa's balance as the stall's. No row is "
          'added to Personal.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('restore-check-answer')));
      await _settle(tester);
      expect(find.text('They were mine'), findsNothing);
      await _done(tester);
    });
  });

  group('Clear data', () {
    testWidgets("asks about the stall's money on your M-Pesa, with the "
        "delete sheet's words", (tester) async {
      await _pump(tester, screen: const ClearSpaceScreen(spaceId: 'stall'));
      expect(
        find.text("KES 650 of your M-Pesa is Vegetable stall's"),
        findsOneWidget,
      );
      expect(find.text('It is mine now'), findsOneWidget);
      expect(
        find.text('It is filed as pay from Vegetable stall.'),
        findsOneWidget,
      );
      await _choose(
        tester,
        const Key('space-delete-held-choice'),
        const Key('space-delete-held-apart'),
      );
      expect(
        find.text(
          'It stays held for Vegetable stall, on your Home, until you settle '
          'it.',
        ),
        findsOneWidget,
      );
      // The confirm dialog does not repeat the answer.
      await tester.ensureVisible(find.byKey(const Key('clear-confirm')));
      await tester.tap(find.byKey(const Key('clear-confirm')));
      await _settle(tester);
      expect(find.text('Clear Vegetable stall?'), findsOneWidget);
      expect(find.textContaining('filed as pay'), findsNothing);
      await _done(tester);
    });

    testWidgets('a business with nothing on your accounts is not asked', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const ClearSpaceScreen(spaceId: 'stall'),
        before: (dbs) => dbs.personal.delete(dbs.personal.balanceRecords).go(),
      );
      expect(find.text('It is mine now'), findsNothing);
      await _done(tester);
    });
  });
}
