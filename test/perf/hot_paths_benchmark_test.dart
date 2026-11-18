// Host benchmarks of the app's hot paths on a large synthetic ledger.
//
// These are HOST numbers: an in-memory database on a desktop CPU, with the
// database on the same isolate as the work. A 2-3 GB phone with Cortex-A53
// or A55 cores is several times slower, and there the database runs in its
// own isolate. They show what got faster and catch regressions; they do not
// say how long anything takes on a phone (see tool/startup_timing.sh).
//
// Print the table:
//   flutter test test/perf/hot_paths_benchmark_test.dart --dart-define=PERF_REPORT=true
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/not_yet_sorted_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';

import 'synthetic_ledger.dart';

const _report = bool.fromEnvironment('PERF_REPORT');

/// Generous ceilings, in host milliseconds of wall time: four to five
/// times what each took on the machine that set them (journal first sync
/// 1.7 s, sync after one new message 0.5 s, journal read 0.35 s, whole
/// ledger 0.3 s, one month 8 ms, Home 1.1 s), so a busy machine does not
/// fail them. Only a large regression, such as Home reading the ledger
/// once per card again or a loop turning quadratic, should cross one.
const _ceilings = {
  'journal first sync': 8000,
  'journal sync after one new': 2500,
  'journal read': 2000,
  'ledgerEntries all time': 1500,
  'ledgerEntries one month': 150,
  'Home, all cards': 5000,
};

/// Timed runs per measure: medians of five for the table, two otherwise
/// to keep the test suite quick.
const _runs = _report ? 5 : 2;

void main() {
  late AppDatabase db;
  late SyntheticLedger ledger;
  final results = <String, Timing>{};

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    ledger = await seedSyntheticLedger(db);
  });

  tearDownAll(() async {
    await db.close();
    if (!_report) return;
    String ms(Duration? d) => d == null
        ? '-'.padLeft(8)
        : (d.inMicroseconds / 1000).toStringAsFixed(0).padLeft(8);
    // ignore: avoid_print
    print(
      '\nHost benchmark, ${ledger.transactionCount} synthetic transactions '
      'over two years (median ms)\n'
      '${'what'.padRight(34)}     wall      cpu',
    );
    for (final MapEntry(:key, :value) in results.entries) {
      // ignore: avoid_print
      print('${key.padRight(34)} ${ms(value.wall)} ${ms(value.cpu)}');
    }
  });

  void check(String name, Timing timing) {
    results[name] = timing;
    final ceiling = _ceilings[name];
    if (ceiling != null) {
      expect(
        timing.wall.inMilliseconds,
        lessThan(ceiling),
        reason: '$name took ${timing.wall.inMilliseconds} ms on this host',
      );
    }
  }

  test('journal', timeout: Timeout.none, () async {
    final journal = JournalRepository(db);
    final cpu = processCpuMicros();
    final watch = Stopwatch()..start();
    await journal.sync();
    final cpuAfter = processCpuMicros();
    check('journal first sync', (
      wall: watch.elapsed,
      cpu: cpu == null || cpuAfter == null || cpuAfter < cpu
          ? null
          : Duration(microseconds: cpuAfter - cpu),
    ));

    var n = 0;
    check(
      'journal sync after one new',
      await medianTime(runs: _runs, () async {
        await DriftTransactionsRepository(db).addNew([
          TransactionsCompanion.insert(
            accountId: ledger.accountIds.first,
            occurredAt: ledger.end.subtract(Duration(minutes: ++n)),
            amountMinor: 5000,
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.till),
            source: TransactionSource.sms,
            dedupeKey: Value('bench-$n'),
          ),
        ]);
        await journal.sync();
      }),
    );
    check('journal read', await medianTime(journal.read, runs: _runs));
  });

  test('ledger reads', timeout: Timeout.none, () async {
    final repo = DriftTransactionsRepository(db);
    check(
      'ledgerEntries all time',
      await medianTime(
        runs: _runs,
        () => repo.ledgerEntries(
          from: DateTime.utc(1970),
          to: DateTime.utc(3000),
        ),
      ),
    );
    check(
      'ledgerEntries one month',
      await medianTime(
        runs: _runs,
        () => repo.ledgerEntries(
          from: DateTime.utc(2026, 10),
          to: DateTime.utc(2026, 11),
        ),
      ),
    );
    check(
      'ledgerEntries one month, one tag',
      await medianTime(
        runs: _runs,
        () => repo.ledgerEntries(
          from: DateTime.utc(2026, 10),
          to: DateTime.utc(2026, 11),
          tagId: ledger.tagIds.first,
        ),
      ),
    );
  });

  /// Reads [providers] together in a fresh container, as a screen opening
  /// does, listening so none is paused.
  Future<Timing> screen(List<FutureProvider<Object?>> providers) =>
      medianTime(() async {
        final c = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(() => ledger.end),
          ],
        );
        for (final p in providers) {
          c.listen(p, (_, _) {});
        }
        await Future.wait([for (final p in providers) c.read(p.future)]);
        c.dispose();
      }, runs: _report ? 3 : 1);

  test('screens', timeout: Timeout.none, () async {
    check(
      'Home, all cards',
      await screen([
        safeToSpendTodayProvider,
        healthIndexProvider,
        cashFlowForecastProvider,
        upcomingBillsProvider,
        notYetSortedProvider,
      ]),
    );
    check('Home: not yet sorted', await screen([notYetSortedProvider]));
    check('Balances', await screen([balancesOverviewProvider]));
    check(
      'Insights',
      await screen([
        insightsSummaryProvider,
        findingsProvider,
        spendingChartProvider,
      ]),
    );
  });
}
