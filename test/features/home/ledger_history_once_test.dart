import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/ledger_history.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/not_yet_sorted_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';

import '../balances/balances_harness.dart';

/// Counts reads of the whole ledger.
class _CountingTransactions extends DriftTransactionsRepository {
  _CountingTransactions(super.db, {super.converter});

  int wholeLedgerReads = 0;

  @override
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
    int? tagId,
    Set<int>? accountIds,
    Set<int>? ids,
    bool dayToDayOnly = false,
  }) {
    if (from.year == 1970 && to.year == 9999 && ids == null) {
      wholeLedgerReads++;
    }
    return super.ledgerEntries(
      from: from,
      to: to,
      tagId: tagId,
      accountIds: accountIds,
      ids: ids,
      dayToDayOnly: dayToDayOnly,
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late _CountingTransactions transactions;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedScenario(db);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => scenarioNow),
        transactionsRepositoryProvider.overrideWith(
          (ref) => transactions = _CountingTransactions(
            ref.watch(appDatabaseProvider),
            converter: ref.watch(currencyConverterProvider),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // Every Home and Balances card that reads years of history.
  final readers = <ProviderListenable<Future<Object?>>>[
    safeToSpendTodayProvider.future,
    healthIndexProvider.future,
    cashFlowForecastProvider.future,
    notYetSortedProvider.future,
    onHandProvider.future,
    balancesOverviewProvider.future,
  ];

  Future<void> settled() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final p in readers) {
        await container.read(p);
      }
    }
  }

  test('they read the whole ledger once per change', () async {
    for (final p in readers) {
      container.listen(p, (_, _) {});
    }
    await settled();
    expect(transactions.wholeLedgerReads, 1);

    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Example Bank',
            type: AccountType.bank,
            openingDate: scenarioNow,
            openingBalanceMinor: const Value(50000),
          ),
        );
    await settled();
    expect(transactions.wholeLedgerReads, 2);
  });

  test('a slice of the shared read is what the database gives for the '
      'same range', () async {
    final repo = DriftTransactionsRepository(db);
    final all = await repo.ledgerEntries(
      from: DateTime.utc(1970),
      to: DateTime.utc(9999),
    );
    expect(all, isNotEmpty);
    final times = {for (final e in all) e.occurredAt};
    // Each entry's own time, a millisecond either side, and none at all.
    final bounds = <DateTime>[
      DateTime.utc(1970),
      for (final t in times) ...[
        t,
        t.add(const Duration(milliseconds: 1)),
        t.subtract(const Duration(milliseconds: 1)),
        t.add(const Duration(seconds: 1)),
      ],
      DateTime.utc(9999),
    ];
    for (final from in bounds) {
      for (final to in [
        ...bounds.where((b) => b.isAfter(from)).take(4),
        DateTime.utc(9999),
      ]) {
        final direct = await repo.ledgerEntries(from: from, to: to);
        expect(
          entriesBetween(all, from: from, to: to).map((e) => e.id),
          direct.map((e) => e.id),
          reason: 'from $from to $to',
        );
      }
    }
  });
}
