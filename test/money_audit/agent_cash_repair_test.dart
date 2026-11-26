import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/balances_repair.dart';
import 'package:pesaclarity/src/data/repositories/message_links.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';

import '../domain/fixtures.dart';

/// Agent withdrawals and deposits stored before agent cash moved to a cash
/// account get their side there, once. Made-up data.
void main() {
  late AppDatabase db;
  late int mpesa;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            institutionId: const Value('mpesa'),
            openingDate: eat(2026, 11, 1, 0),
            openingBalanceMinor: Value(kes(5000)),
          ),
        );
    Future<void> add(TransactionKind kind, int amount, int day) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            occurredAt: eat(2026, 11, day, 10),
            amountMinor: amount,
            direction: kind == TransactionKind.withdrawal
                ? TransactionDirection.outflow
                : TransactionDirection.inflow,
            kind: Value(kind),
            source: TransactionSource.sms,
          ),
        );
    // Out 1,000, then 3,000 put in: more in than the records took out.
    await add(TransactionKind.withdrawal, kes(1000), 3);
    await add(TransactionKind.deposit, kes(3000), 5);
  });

  tearDown(() => db.close());

  Future<List<TransactionRecord>> onCash() async {
    final cash = await (db.select(
      db.accounts,
    )..where((a) => a.type.equalsValue(AccountType.cash))).getSingle();
    expect(cash.name, cashInHandName);
    return (db.select(db.transactions)
          ..where((t) => t.accountId.equals(cash.id))
          ..orderBy([(t) => OrderingTerm(expression: t.occurredAt)]))
        .get();
  }

  test('the repair gives old agent cash its side, once', () async {
    await repairBalances(db);
    final first = await onCash();
    expect(first.map((t) => (t.direction, t.amountMinor)), [
      (TransactionDirection.inflow, kes(1000)),
      (TransactionDirection.outflow, kes(3000)),
    ]);
    final all = await db.select(db.transactions).get();
    expect(all.every((t) => t.transferPairId != null), isTrue);

    await repairBalances(db);
    expect(await linkStoredAgentCash(db), 0);
    expect(await onCash(), hasLength(2));
    expect(await db.select(db.transactions).get(), hasLength(4));
  });

  test('cash below zero is a problem to set right', () async {
    await repairBalances(db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => eat(2026, 11, 10)),
      ],
    );
    addTearDown(container.dispose);
    final overview = await container.read(balancesOverviewProvider.future);
    final short = overview.cashBelowZero;
    expect(short, hasLength(1));
    expect(short.single.heldMinor, -kes(2000));
  });
}
