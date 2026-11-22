// Editing and removing an account, and SACCOs, for the accessibility check
// (tool/accessibility.sh): an account added by hand, one read from
// messages, the remove choices, Add a SACCO in both steps, a SACCO's page
// and My accounts with its SACCO. Not marketing screenshots, so
// tool/screenshots.sh skips them. Made-up names, numbers and amounts.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sacco_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/presentation/account_page.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/accounts/presentation/sacco_screens.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Sunday 22 November 2026, 09:41 in Nairobi.
final _now = eat(2026, 11, 22, 9, 41);

late int _tumaini;
late int _equity;
late int _mwangaza;

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Cash',
          type: AccountType.cash,
          openingDate: eat(2026, 1, 1),
          openingBalanceMinor: Value(kes(3500)),
        ),
      );
  _tumaini = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Tumaini SACCO',
          type: AccountType.bank,
          openingDate: eat(2026, 1, 1),
          openingBalanceMinor: Value(kes(8000)),
        ),
      );
  for (var m = 1; m <= 11; m++) {
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: _tumaini,
            occurredAt: eat(2026, m, 5),
            amountMinor: kes(400),
            direction: TransactionDirection.inflow,
            source: TransactionSource.manual,
          ),
        );
  }
  _equity = await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Equity Bank ···4321',
          type: AccountType.bank,
          openingDate: eat(2026, 1, 1),
          institutionId: const Value('equity'),
          reference: const Value('0170*****4321'),
        ),
      );
  _mwangaza = await SaccoRepository(db).add(
    name: 'Mwangaza SACCO',
    currency: 'KES',
    paybill: '400222',
    depositsMinor: kes(84000),
    sharesMinor: kes(20000),
    contributionMinor: kes(3000),
    borrowTimesTenths: 30,
    at: eat(2026, 10, 1, 9),
    loan: SaccoLoanInput(
      owedMinor: kes(150000),
      monthlyMinor: kes(6500),
      rateBasisPoints: 1200,
      checkOffDay: 28,
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  final db = openTestDatabase();
  await tester.runAsync(() => _seed(db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        personalDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => _now),
        deviceRegionProvider.overrideWithValue('KE'),
        activeSpaceProvider.overrideWithValue(Space.personal),
        ...appLockOverrides(),
      ],
      child: shotApp(home),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

Widget _late(Widget Function() build) => Builder(builder: (_) => build());

void main() {
  if (!checkAccessibility) return;

  screenshot('my-accounts-sacco', (tester) async {
    await _pump(tester, const MyAccountsSettingsScreen());
    await snap(tester);
  });

  screenshot('account-edit', (tester) async {
    await _pump(tester, _late(() => AccountPage(accountId: _tumaini)));
    await snap(tester);
    await tester.tap(find.byKey(const Key('account-type')));
    await tester.pumpAndSettle();
    await snap(tester, variant: 'type');
  });

  screenshot('account-edit-messages', (tester) async {
    await _pump(tester, _late(() => AccountPage(accountId: _equity)));
    await snap(tester);
  });

  screenshot('account-remove', (tester) async {
    await _pump(tester, _late(() => AccountPage(accountId: _tumaini)));
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-remove')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(const Key('account-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-remove')));
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester);
    await tester.tap(find.byKey(const Key('remove-move')));
    await tester.pumpAndSettle();
    await snap(tester, variant: 'move');
  });

  screenshot('sacco-add', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showAddSaccoSheet(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sacco-name')), 'Mwangaza');
    await tester.tap(find.byKey(const Key('sacco-has-loan')));
    await tester.pumpAndSettle();
    await snap(tester);
    await tester.ensureVisible(find.byKey(const Key('sacco-continue')));
    await tester.tap(find.byKey(const Key('sacco-continue')));
    await tester.pumpAndSettle();
    await snap(tester, variant: 'loan');
  });

  screenshot('sacco-page', (tester) async {
    await _pump(tester, _late(() => SaccoScreen(accountId: _mwangaza)));
    await snap(tester);
  });
}
