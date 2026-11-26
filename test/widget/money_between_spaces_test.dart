// What each space shows of money between spaces (decision 0027, section
// 5): Personal's Balances and On hand say how much of M-Pesa is the
// stall's, the stall's Money shows it on its own line beside Cash and
// Bank, and Personal's Activity has no row for the switched sale. Made-up
// records only.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/balances/presentation/balances_screen.dart';
import 'package:pesaclarity/src/features/balances/presentation/on_hand_sheet.dart';
import 'package:pesaclarity/src/features/books/presentation/money_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';

final _now = eat(2026, 11, 21, 9, 41);

const _stall = Space(
  id: 'stall',
  name: 'Vegetable stall',
  kind: SpaceKind.business,
);

/// Personal's M-Pesa with KES 37,819, Grace Wambui's KES 650 switched to
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
          occurredAt: eat(2026, 11, 20, 17, 6),
          amountMinor: 65000,
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyName: const Value('GRACE WAMBUI'),
          receiptNo: const Value('TKK7QX2M4P'),
          dedupeKey: const Value('TKK7QX2M4P|65000'),
          balanceAfterMinor: const Value(3846900),
        ),
      );
  await DriftSpaceMoveRepository(
    personal,
    (_) async => (business, false),
    nameOf: (id) async => id == _stall.id ? _stall.name : 'Personal',
  ).move(sale, _stall.id);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  bool inStall = false,
}) async {
  final personal = openTestDatabase();
  final business = openTestDatabase();
  await tester.runAsync(() async {
    await business.becomeSpace(SpaceKind.business);
    await _seed(personal, business);
  });
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(inStall ? business : personal),
      personalDatabaseProvider.overrideWithValue(personal),
      mainDatabaseProvider.overrideWithValue(personal),
      clockProvider.overrideWithValue(() => _now),
      deviceRegionProvider.overrideWithValue('KE'),
      activeSpaceProvider.overrideWithValue(inStall ? _stall : Space.personal),
      activeSpaceIdProvider.overrideWith(
        () => ActiveSpaceId(inStall ? _stall.id : personalSpaceId),
      ),
      ...appLockOverrides(),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the screen go, and the database work it started finish.
Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets("Balances: M-Pesa shows the wallet, KES 650 of it the stall's", (
    tester,
  ) async {
    await _pump(tester, const BalancesScreen());
    expect(find.text('38,469'), findsWidgets);
    expect(find.text("KES 650 of this is Vegetable stall's"), findsOneWidget);
    await _done(tester);
  });

  testWidgets('On hand says it, and that safe to spend leaves it out', (
    tester,
  ) async {
    await _pump(tester, const Scaffold(body: OnHandSheet()));
    expect(
      find.textContaining(
        "KES 650 of this is Vegetable stall's. Safe to spend leaves it out.",
      ),
      findsOneWidget,
    );
    await _done(tester);
  });

  testWidgets("the stall's Money: On your M-Pesa 650 beside Cash and Bank, "
      'and the sale tagged Your M-Pesa', (tester) async {
    await _pump(tester, const MoneyScreen(), inStall: true);
    expect(find.text('On your M-Pesa'), findsOneWidget);
    expect(find.text('650'), findsWidgets);
    expect(find.textContaining('Your M-Pesa'), findsWidgets);
    await _done(tester);
  });
}
