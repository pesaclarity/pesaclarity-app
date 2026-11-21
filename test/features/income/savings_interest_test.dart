import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/savings_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/savings/savings_product.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';

// Made-up money: a salary into M-Pesa, payments to the Chumz paybill and a
// balance typed for Chumz that shows interest.

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int mpesa;
  late int chumzId;

  // Saturday 21 November 2026, 10:00 EAT.
  final now = DateTime.utc(2026, 11, 21, 7);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026, 8),
            institutionId: const Value('mpesa'),
          ),
        );
    final transactions = DriftTransactionsRepository(db);
    await transactions.addNew([
      // A salary on the 25th of each month.
      for (final month in [8, 9, 10])
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: DateTime.utc(2026, month, 25, 6),
          amountMinor: 5000000,
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyKind: const Value(PayeeIdentifierKind.paybill),
          counterpartyValue: const Value('EXAMPLE EMPLOYER LTD'),
          counterpartyName: const Value('EXAMPLE EMPLOYER LTD'),
          receiptNo: Value('TKS000000$month'),
          dedupeKey: Value('TKS000000$month|5000000'),
        ),
      // Paid into Chumz the day after.
      for (final month in [8, 9, 10])
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: DateTime.utc(2026, month, 26, 6),
          amountMinor: 1000000,
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.paybill),
          source: TransactionSource.sms,
          counterpartyKind: const Value(PayeeIdentifierKind.paybill),
          counterpartyValue: const Value('NABO CAPITAL LTD C2B#CH12345'),
          counterpartyName: const Value('NABO CAPITAL LTD C2B'),
          receiptNo: Value('TKP000000$month'),
          dedupeKey: Value('TKP000000$month|1000000'),
        ),
    ]);
    final savings = DriftSavingsRepository(db);
    chumzId = (await savings.add(chumz, at: now)).accountId;
    final pocket = (await savings.account(chumzId))!.pockets.single.id;
    // Typed this morning: 300 shillings more than was paid in.
    await savings.updateBalances(
      chumzId,
      balanceByPocket: {pocket: 3030000},
      at: DateTime.utc(2026, 11, 21, 6),
    );
    await savings.dispose();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('interest on a savings account is income', () async {
    final entries = await DriftTransactionsRepository(db)
        .ledgerEntries(from: DateTime.utc(2026), to: DateTime.utc(2027));
    final interest = entries.singleWhere(
      (e) => e.accountId == chumzId && e.isInflow && e.transferPairId == null,
    );
    expect(interest.amountMinor, 30000);
    expect(roleOf(interest), LedgerRole.income);
    final november = YearMonth(2026, 11);
    final totals = LedgerTotals.of(
      entries,
      from: november.startInstant,
      to: november.endInstant,
      currency: 'KES',
    );
    expect(totals.incomeMinor, 30000);
  });

  test('but it is not money arriving to spend', () async {
    final latest = await container.read(latestArrivalProvider.future);
    expect(latest!.accountId, mpesa);
    expect(latest.occurredAt.toUtc(), DateTime.utc(2026, 10, 25, 6));

    final pattern = await container.read(incomePatternProvider.future);
    expect(pattern.arrivalDays, 3);
    expect(pattern.senders, 1);
    expect(pattern.lastArrival, CalendarDate(2026, 10, 25));

    // Nothing came in this week.
    final weeks = await container.read(weekByWeekProvider.future);
    expect(weeks.weeks.last.inMinor, 0);
  });
}
