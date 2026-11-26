import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/debts/application/debts_overview_provider.dart';
import 'package:pesaclarity/src/features/plan/application/plan_providers.dart';

import '../domain/fixtures.dart';
import '../features/balances/balances_harness.dart';

/// Plan's spent and the Debts screen's Fuliza follow a new transaction
/// without leaving the screen. Made-up data.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ScenarioAccounts accounts;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    accounts = await seedScenario(db);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => scenarioNow),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<T> settled<T>(Future<T> Function() read) async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await read();
    }
    return read();
  }

  test('Plan and Debts recompute when the ledger changes', () async {
    final month = YearMonth.local(scenarioNow);
    final plan = planViewProvider(month);
    container
      ..listen(plan, (_, _) {})
      ..listen(debtsOverviewProvider, (_, _) {});
    int spent(PlanView v) =>
        v.review.categories.fold(0, (s, c) => s + c.actualMinor);
    final before = spent(await settled(() => container.read(plan.future)));
    final fulizaBefore =
        (await settled(() => container.read(debtsOverviewProvider.future)))
            .fuliza
            ?.usage
            .drawsMinor ??
        0;

    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: accounts.mpesa,
            occurredAt: eat(2026, 11, 14, 9),
            amountMinor: kes(700),
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.till),
            source: TransactionSource.manual,
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: accounts.mpesa,
            occurredAt: eat(2026, 11, 14, 9, 30),
            amountMinor: kes(200),
            direction: TransactionDirection.inflow,
            kind: const Value(TransactionKind.fulizaDraw),
            source: TransactionSource.sms,
          ),
        );

    final after = spent(await settled(() => container.read(plan.future)));
    expect(after, before + kes(700));
    final fulizaAfter =
        (await settled(() => container.read(debtsOverviewProvider.future)))
            .fuliza
            ?.usage
            .drawsMinor ??
        0;
    expect(fulizaAfter, fulizaBefore + kes(200));
  });
}
