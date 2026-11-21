// After a switch, every figure read from the journal (On hand, Balances,
// business Home, Start your records, Ask) is the open space's own, however
// many changes each space has seen. Made-up data only.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/business_setup_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

const _shopId = 'shop1';
const _shop = Space(id: _shopId, name: 'Test Shop', kind: SpaceKind.business);

int _kes(int shillings) => shillings * 100;

void main() {
  late AppDatabase personal;
  late AppDatabase shop;
  late ProviderContainer c;

  /// KES [shillings] in or out of account 1 of [db].
  Future<void> money(
    AppDatabase db,
    int shillings, {
    required TransactionDirection way,
    required int day,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: 1,
          occurredAt: DateTime.utc(2026, 11, day, 6),
          amountMinor: _kes(shillings),
          direction: way,
          source: TransactionSource.manual,
        ),
      );

  Future<int> held() async =>
      (await c.read(balancesOverviewProvider.future)).accounts.single.heldMinor;

  Future<void> open(String spaceId) =>
      c.read(activeSpaceIdProvider.notifier).switchTo(spaceId);

  setUp(() async {
    personal = openTestDatabase();
    shop = openTestDatabase();
    await shop.becomeSpace(SpaceKind.business);
    await DriftAppSettingsRepository(personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson(const [Space.personal, _shop]),
    );
    // Account 1 in each: Personal's M-Pesa holds KES 14,000, the shop's
    // bank KES 2,000.
    await personal
        .into(personal.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingBalanceMinor: Value(_kes(14000)),
            openingDate: DateTime.utc(2026, 11),
            institutionId: const Value('mpesa'),
          ),
        );
    await shop
        .into(shop.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Test Bank',
            type: AccountType.bank,
            openingBalanceMinor: Value(_kes(2000)),
            openingDate: DateTime.utc(2026, 11),
          ),
        );
    c = twoSpaces(
      personal: personal,
      other: shop,
      clock: () => DateTime.utc(2026, 11, 20, 9),
    );
  });

  test(
    'opened from Personal, the shop shows its own balance everywhere',
    () async {
      expect((await c.read(onHandProvider.future))!.totalMinor, _kes(14000));

      await open(_shopId);
      await c.read(spacesProvider.future);

      expect((await c.read(onHandProvider.future))!.totalMinor, _kes(2000));
      final balances = await c.read(balancesOverviewProvider.future);
      expect(
        (
          balances.accounts.single.account.name,
          balances.accounts.single.heldMinor,
        ),
        ('Test Bank', _kes(2000)),
      );
      expect(
        (await c.read(spaceSummaryProvider.future))!.balanceMinor,
        _kes(2000),
      );
      expect(
        (await c.read(openingLinesProvider.future)).single.suggestedMinor,
        _kes(2000),
      );
      final ask = (await c.read(askDataSourceProvider).balances()).single;
      expect((ask.name, ask.amountMinor), ('Test Bank', _kes(2000)));
    },
  );

  test('once the shop has seen as many changes as Personal had, it still '
      'shows its own', () async {
    final watching = c.listen(balancesOverviewProvider, (_, _) {});
    addTearDown(watching.close);
    await held();
    await money(personal, 1000, way: TransactionDirection.outflow, day: 4);
    await settle(100);
    expect(await held(), _kes(13000));

    await open(_shopId);
    expect(await held(), _kes(2000));
    await money(shop, 500, way: TransactionDirection.outflow, day: 5);
    await settle(100);
    expect(await held(), _kes(1500));
  });

  test('back in Personal, Personal is shown its own again, with what '
      'changed meanwhile', () async {
    final watching = c.listen(balancesOverviewProvider, (_, _) {});
    addTearDown(watching.close);
    expect(await held(), _kes(14000));
    await open(_shopId);
    expect(await held(), _kes(2000));
    await money(shop, 500, way: TransactionDirection.outflow, day: 5);
    await settle(100);
    expect(await held(), _kes(1500));

    await open(personalSpaceId);
    expect(await held(), _kes(14000));
    await money(personal, 1000, way: TransactionDirection.outflow, day: 6);
    await settle(100);
    expect(await held(), _kes(13000));
  });

  test('one read is shared per space and change, never across '
      'spaces', () async {
    await c.read(onHandProvider.future);
    final converter = c.read(currencyConverterProvider);
    final inPersonal = c.read(journalRepositoryProvider);
    await open(_shopId);
    final inShop = c.read(journalRepositoryProvider);
    expect(inShop, isNot(same(inPersonal)));

    final generation = inShop.generation;
    final a = await c.read(
      journalAtGenerationProvider((generation, converter, inShop)).future,
    );
    final b = await c.read(
      journalAtGenerationProvider((generation, converter, inShop)).future,
    );
    expect(b, same(a));
    final personalRead = await c.read(
      journalAtGenerationProvider((generation, converter, inPersonal)).future,
    );
    expect(personalRead, isNot(same(a)));
  });
}
