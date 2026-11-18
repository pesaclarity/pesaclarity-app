import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';

/// A made-up but realistic ledger for timing the app's hot paths on the
/// host: about [count] transactions over two years across an M-Pesa wallet,
/// a bank account and a SACCO, with payees, categories, tags and a plan.
///
/// Every value is synthetic. Phone numbers use the 0700 000 000 range.
/// The same seed always builds the same ledger, so timings compare.
Future<SyntheticLedger> seedSyntheticLedger(
  AppDatabase db, {
  int count = 20000,
  DateTime? end,
  int seed = 42,
}) async {
  final until = end ?? DateTime.utc(2026, 10, 26, 5);
  final start = until.subtract(const Duration(days: 730));
  final random = Random(seed);

  Future<int> account(String name, AccountType type, int opening) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingBalanceMinor: Value(opening),
          openingDate: start,
          institutionId: Value(type == AccountType.mpesa ? 'mpesa' : null),
        ),
      );

  final mpesa = await account('M-Pesa', AccountType.mpesa, 2000000);
  final bank = await account('Bank', AccountType.bank, 15000000);
  final sacco = await account('SACCO', AccountType.sacco, 5000000);
  final accounts = [mpesa, mpesa, mpesa, bank, sacco];

  final categories = await db.select(db.categories).get();
  final expense = [
    for (final c in categories)
      if (c.type == CategoryType.expense) c.id,
  ];
  final income = [
    for (final c in categories)
      if (c.type == CategoryType.income) c.id,
  ];
  final daily = categories.firstWhere(
    (c) => c.isDailySpending,
    orElse: () => categories.first,
  );

  final payees = <int>[];
  await db.batch((b) {
    for (var i = 0; i < 300; i++) {
      b.insert(
        db.payees,
        PayeesCompanion.insert(
          displayName: 'Payee $i',
          defaultCategoryId: Value(
            i.isEven ? expense[i % expense.length] : null,
          ),
          leakType: Value(LeakType.values[i % LeakType.values.length]),
        ),
      );
    }
  });
  for (final p in await db.select(db.payees).get()) {
    payees.add(p.id);
  }

  final tags = <int>[
    for (final name in ['Work', 'Trip', 'Family'])
      await db.into(db.tags).insert(TagsCompanion.insert(name: name)),
  ];

  // Rent, salary and a day-to-day budget, so Home has a plan to work with.
  await db
      .into(db.recurring)
      .insert(
        RecurringCompanion.insert(
          name: 'Rent',
          categoryId: Value(expense.first),
          amountMinor: 2500000,
          frequency: RecurrenceFrequency.monthly,
          startDate: start,
        ),
      );
  await db
      .into(db.recurring)
      .insert(
        RecurringCompanion.insert(
          name: 'Food and transport',
          categoryId: Value(daily.id),
          amountMinor: 3000000,
          frequency: RecurrenceFrequency.monthly,
          startDate: start,
        ),
      );

  const kinds = [
    TransactionKind.sent,
    TransactionKind.paybill,
    TransactionKind.till,
    TransactionKind.withdrawal,
    TransactionKind.airtime,
  ];
  final span = until.difference(start).inMinutes;
  final rows = <TransactionsCompanion>[];
  for (var i = 0; i < count; i++) {
    final at = start.add(Duration(minutes: random.nextInt(span)));
    final inflow = random.nextInt(5) == 0;
    final accountId = accounts[random.nextInt(accounts.length)];
    final payee = random.nextInt(3) == 0
        ? null
        : payees[random.nextInt(payees.length)];
    final override = random.nextInt(6) == 0
        ? (inflow ? income : expense)[random.nextInt(
            (inflow ? income : expense).length,
          )]
        : null;
    rows.add(
      TransactionsCompanion.insert(
        accountId: accountId,
        occurredAt: at,
        amountMinor: inflow
            ? 50000 + random.nextInt(2000000)
            : 1000 + random.nextInt(300000),
        direction: inflow
            ? TransactionDirection.inflow
            : TransactionDirection.outflow,
        kind: Value(
          inflow
              ? TransactionKind.received
              : kinds[random.nextInt(kinds.length)],
        ),
        feeMinor: Value(inflow ? 0 : random.nextInt(5000)),
        payeeId: Value(payee),
        counterpartyKind: const Value(PayeeIdentifierKind.phone),
        counterpartyValue: Value(
          '0700000${random.nextInt(1000).toString().padLeft(3, '0')}',
        ),
        counterpartyName: Value('Person ${random.nextInt(1000)}'),
        categoryOverrideId: Value(override),
        receiptNo: Value('SYN${i.toString().padLeft(7, '0')}'),
        dedupeKey: Value('syn-$i'),
        messageHash: Value('hash-$i'),
        source: TransactionSource.sms,
      ),
    );
  }
  await db.batch((b) => b.insertAll(db.transactions, rows));

  // About one in twenty is tagged.
  final ids =
      await (db.selectOnly(db.transactions)..addColumns([db.transactions.id]))
          .map((r) => r.read(db.transactions.id)!)
          .get();
  await db.batch((b) {
    for (final id in ids) {
      if (random.nextInt(20) == 0) {
        b.insert(
          db.transactionTags,
          TransactionTagsCompanion.insert(
            transactionId: id,
            tagId: tags[random.nextInt(tags.length)],
          ),
        );
      }
    }
  });

  return SyntheticLedger(
    start: start,
    end: until,
    accountIds: [mpesa, bank, sacco],
    tagIds: tags,
    transactionCount: count,
  );
}

class SyntheticLedger {
  const SyntheticLedger({
    required this.start,
    required this.end,
    required this.accountIds,
    required this.tagIds,
    required this.transactionCount,
  });

  final DateTime start;
  final DateTime end;
  final List<int> accountIds;
  final List<int> tagIds;
  final int transactionCount;
}

/// How long [body] took: wall time, and the CPU time this process spent
/// (every thread, from `/proc`), which other work on a shared machine
/// barely moves. CPU time is null where `/proc` is missing.
typedef Timing = ({Duration wall, Duration? cpu});

/// Runs [body] [runs] times after one warm-up and returns the median of
/// each measure, which is steadier than the mean on a shared machine.
Future<Timing> medianTime(Future<void> Function() body, {int runs = 5}) async {
  await body();
  final walls = <int>[];
  final cpus = <int>[];
  for (var i = 0; i < runs; i++) {
    final cpu = processCpuMicros();
    final watch = Stopwatch()..start();
    await body();
    walls.add(watch.elapsedMicroseconds);
    final after = processCpuMicros();
    if (cpu != null && after != null) cpus.add(after - cpu);
  }
  int median(List<int> xs) => (xs..sort())[xs.length ~/ 2];
  return (
    wall: Duration(microseconds: median(walls)),
    cpu: cpus.isEmpty ? null : Duration(microseconds: median(cpus)),
  );
}

/// CPU time used so far by every thread of this process, in microseconds,
/// or null where `/proc` is not available.
int? processCpuMicros() {
  try {
    var nanos = 0;
    for (final task in Directory('/proc/self/task').listSync()) {
      final stat = File('${task.path}/schedstat').readAsStringSync();
      nanos += int.parse(stat.split(' ').first);
    }
    return nanos ~/ 1000;
  } on Object {
    return null;
  }
}
