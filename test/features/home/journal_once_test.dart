import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/journal_balances.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';

import '../balances/balances_harness.dart';

/// Counts how often the journal is read.
class _CountingJournal extends JournalRepository {
  _CountingJournal(super.db, {super.changes});

  int reads = 0;

  @override
  Future<JournalBalances> read({CurrencyConverter? converter}) {
    reads++;
    return super.read(converter: converter);
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late _CountingJournal journal;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedScenario(db);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => scenarioNow),
        journalRepositoryProvider.overrideWith(
          (ref) =>
              journal = _CountingJournal(db, changes: ledgerTableUpdates(db)),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // Every Home card that needs balances.
  final home = <ProviderListenable<Future<Object?>>>[
    safeToSpendTodayProvider.future,
    untilNextMoneyProvider.future,
    healthIndexProvider.future,
    cashFlowForecastProvider.future,
  ];

  Future<void> settled() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final p in home) {
        await container.read(p);
      }
    }
  }

  test("Home's providers read the journal once per change", () async {
    for (final p in home) {
      container.listen(p, (_, _) {});
    }
    await settled();
    expect(journal.reads, 1);

    // A change to the ledger: every card recomputes, from one new read.
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
    expect(journal.reads, 2);
  });
}
