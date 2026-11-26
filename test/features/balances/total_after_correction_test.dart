// The total cash follows a balance set by hand, and leaves out an M-Pesa
// line the person stopped tracking, at once, wherever a total shows.
// Made-up data only.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/features/accounts/application/mpesa_lines_providers.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/goals/application/goals_overview_provider.dart';

import '../../helpers/spaces_harness.dart';
import '../../helpers/test_app.dart';

int _kes(int shillings) => shillings * 100;

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  /// A message on account [accountId] spending [shillings], leaving
  /// [after].
  Future<void> sms(
    int accountId,
    int shillings, {
    required int day,
    required int after,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: DateTime.utc(2026, 11, day, 6),
          amountMinor: _kes(shillings),
          direction: TransactionDirection.outflow,
          source: TransactionSource.sms,
          balanceAfterMinor: Value(_kes(after)),
        ),
      );

  Future<int> line(String id) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026, 11),
          institutionId: const Value(mpesaInstitutionId),
          reference: Value(lineReference(id)),
        ),
      );

  Future<int> balances() async =>
      (await c.read(balancesOverviewProvider.future)).totalMinor('KES');
  Future<int> onHand() async =>
      (await c.read(onHandProvider.future))!.accountsMinor;
  Future<int> netWorth() async =>
      (await c.read(goalsOverviewProvider.future)).netWorth.assetsMinor;

  late int one;

  setUp(() async {
    db = openTestDatabase();
    one = await line('1');
    final two = await line('2');
    await DriftAppSettingsRepository(db).writeJson(
      mpesaLinesKey,
      const MpesaLines(
        split: true,
        lines: [
          MpesaLine(id: '1', sims: {'sim:1'}),
          MpesaLine(id: '2', sims: {'sim:2'}),
        ],
      ).toJson(),
    );
    await sms(one, 100, day: 3, after: 9000);
    await sms(two, 100, day: 4, after: 3000);
    c = twoSpaces(
      personal: db,
      other: openTestDatabase(),
      clock: () => DateTime.utc(2026, 11, 20, 9),
    );
    for (final p in [
      balancesOverviewProvider,
      onHandProvider,
      goalsOverviewProvider,
    ]) {
      final sub = c.listen(p, (_, _) {});
      addTearDown(sub.close);
    }
  });

  test('a balance set by hand replaces the message balance in every '
      'total at once, and a newer message counts on top of it', () async {
    expect(await balances(), _kes(12000));
    expect(await onHand(), _kes(12000));
    expect(await netWorth(), _kes(12000));

    await c
        .read(balancesRepositoryProvider)
        .setBalance(
          one,
          statedMinor: _kes(4000),
          differenceMinor: _kes(-5000),
          at: DateTime.utc(2026, 11, 10, 8),
          currency: 'KES',
        );
    await settle(100);
    expect(await balances(), _kes(7000));
    expect(await onHand(), _kes(7000));
    expect(await netWorth(), _kes(7000));

    await sms(one, 500, day: 12, after: 3500);
    await settle(100);
    expect(await balances(), _kes(6500));
    expect(await onHand(), _kes(6500));
  });

  test('a line no longer tracked leaves every total at once', () async {
    expect(await balances(), _kes(12000));

    await c.read(mpesaLineRoutingProvider).untrack('2', deleteRecords: false);
    await settle(100);
    expect(await balances(), _kes(9000));
    expect(await onHand(), _kes(9000));
    expect(await netWorth(), _kes(9000));
    final listed = await c.read(balancesOverviewProvider.future);
    expect([for (final a in listed.accounts) a.account.id], [one]);
  });
}
