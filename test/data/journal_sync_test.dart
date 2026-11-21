import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import '../domain/books/journal_random_months_test.dart' as months;
import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late JournalRepository journal;

  setUp(() {
    db = openTestDatabase();
    journal = JournalRepository(db, clock: () => eat(2026, 12, 1));
  });

  Future<int> account(String name, AccountType type, {int balance = 0}) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingBalanceMinor: Value(balance),
          openingDate: DateTime.utc(2026, 11),
        ),
      );

  TransactionsCompanion row(LedgerEntry e, int accountId, {int? payeeId}) =>
      TransactionsCompanion.insert(
        accountId: accountId,
        occurredAt: e.occurredAt,
        amountMinor: e.amountMinor,
        direction: e.direction,
        kind: Value(e.kind),
        feeMinor: Value(e.feeMinor),
        source: TransactionSource.sms,
        balanceAfterMinor: Value(e.balanceAfterMinor),
        claimedBalanceMinor: Value(e.claimedBalanceMinor),
        owedAfterMinor: Value(e.owedAfterMinor),
        payeeId: Value(payeeId),
      );

  test('only the accounts that changed are reposted', () async {
    final mpesa = await account('M-Pesa', AccountType.mpesa);
    final kcb = await account('KCB', AccountType.bank);
    await journal.sync();
    final id = await db
        .into(db.transactions)
        .insert(
          row(months.randomMonth(1, DateTime.utc(2026, 11, 2)).first, mpesa),
        );
    expect(
      [for (final d in await db.select(db.journalDirty).get()) d.accountId],
      [mpesa],
    );
    await journal.sync();
    expect(await db.select(db.journalDirty).get(), isEmpty);

    // Moving it marks both accounts.
    await DriftBalancesRepository(db).moveToAccount(id, kcb);
    expect(
      {for (final d in await db.select(db.journalDirty).get()) d.accountId},
      {mpesa, kcb},
    );
  });

  test('a payee or category change marks the accounts that use it', () async {
    final mpesa = await account('M-Pesa', AccountType.mpesa);
    final kcb = await account('KCB', AccountType.bank);
    final payee = await db
        .into(db.payees)
        .insert(PayeesCompanion.insert(displayName: 'Shop'));
    await db
        .into(db.transactions)
        .insert(
          row(
            months.randomMonth(2, DateTime.utc(2026, 11, 2)).first,
            kcb,
            payeeId: payee,
          ),
        );
    await journal.sync();
    final category = (await db.select(db.categories).get()).first;
    await (db.update(db.payees)..where((p) => p.id.equals(payee))).write(
      PayeesCompanion(defaultCategoryId: Value(category.id)),
    );
    expect(
      [for (final d in await db.select(db.journalDirty).get()) d.accountId],
      [kcb],
    );
    await journal.sync();
    await (db.update(db.categories)..where((c) => c.id.equals(category.id)))
        .write(const CategoriesCompanion(isDailySpending: Value(true)));
    expect(
      {for (final d in await db.select(db.journalDirty).get()) d.accountId},
      {mpesa, kcb},
    );
  });

  test('incremental syncs end where a full rebuild does, over random months '
      'and the changes a person makes', () async {
    final r = Random(7);
    final accounts = [
      await account('M-Pesa', AccountType.mpesa, balance: 100000),
      await account('KCB', AccountType.bank, balance: 500000),
      await account('Cash', AccountType.cash, balance: 20000),
    ];
    final categories = await db.select(db.categories).get();
    final ids = <int>[];
    for (var seed = 0; seed < 12; seed++) {
      final target = accounts[seed % accounts.length];
      for (final e in months.randomMonth(seed, DateTime.utc(2026, 11))) {
        ids.add(await db.into(db.transactions).insert(row(e, target)));
      }
      // Sync after each month, and after each of a few changes, as the app
      // does after each write.
      await journal.sync();
      for (var change = 0; change < 6; change++) {
        final id = ids[r.nextInt(ids.length)];
        switch (r.nextInt(4)) {
          case 0:
            await (db.update(
              db.transactions,
            )..where((t) => t.id.equals(id))).write(
              TransactionsCompanion(
                categoryOverrideId: Value(
                  categories[r.nextInt(categories.length)].id,
                ),
              ),
            );
          case 1:
            await DriftBalancesRepository(db)
                .moveToAccount(id, accounts[r.nextInt(accounts.length)]);
          case 2:
            await (db.delete(
              db.transactions,
            )..where((t) => t.id.equals(id))).go();
            ids.remove(id);
          case _:
            await (db.update(
              db.accounts,
            )..where((a) => a.id.equals(accounts[r.nextInt(3)]))).write(
              AccountsCompanion(
                openingBalanceMinor: Value(r.nextInt(100) * 1000),
              ),
            );
        }
        await journal.sync();
      }
    }
    final incremental = await journal.balances();
    final rebuilt = await journal.rebuild();
    expect(rebuilt.changed, isFalse, reason: '$rebuilt');
    expect(await journal.balances(), incremental);
    expect(await journal.unbalanced(), isEmpty);
  });

  test('incremental syncs end where a full rebuild does with own transfers '
      'paired, unpaired and changed on one side, and balances set', () async {
    final r = Random(11);
    final accounts = [
      await account('M-Pesa', AccountType.mpesa, balance: 100000),
      await account('KCB', AccountType.bank, balance: 500000),
      await account('Cash', AccountType.cash, balance: 20000),
    ];
    final transactions = DriftTransactionsRepository(db);
    final balances = DriftBalancesRepository(db);
    final pairs = <(int, int)>[];
    var matched = 0;
    var changedSides = 0;
    var at = DateTime.utc(2026, 11, 1, 8);
    var n = 0;
    TransactionsCompanion move(
      int accountId,
      int amount, {
      bool inflow = false,
      int fee = 0,
    }) => TransactionsCompanion.insert(
      accountId: accountId,
      occurredAt: at,
      amountMinor: amount,
      direction: inflow
          ? TransactionDirection.inflow
          : TransactionDirection.outflow,
      kind: Value(inflow ? TransactionKind.received : TransactionKind.bank),
      feeMinor: Value(fee),
      source: TransactionSource.sms,
      dedupeKey: Value('t${n++}'),
    );
    for (var step = 0; step < 80; step++) {
      at = at.add(Duration(minutes: const [2, 45, 400][r.nextInt(3)]));
      switch (r.nextInt(7)) {
        case 0 || 1:
          // A transfer: what arrived is what left, less a fee on the way,
          // sometimes more; some with a fee the message printed.
          final from = accounts[r.nextInt(3)];
          final to = (accounts.toList()..remove(from))[r.nextInt(2)];
          final left = (r.nextInt(40) + 5) * 10000;
          final lost = const [0, 0, 3000, 5000, -2000][r.nextInt(5)];
          final fee = const [0, 0, 2500][r.nextInt(3)];
          final out = await transactions.add(move(from, left, fee: fee));
          at = at.add(const Duration(minutes: 1));
          final into = await transactions.add(
            move(to, left - lost, inflow: true),
          );
          if (r.nextBool()) {
            await transactions.match(out, into);
            pairs.add((out, into));
            matched++;
          }
        case 2 when pairs.isNotEmpty:
          final (out, _) = pairs.removeAt(r.nextInt(pairs.length));
          await transactions.unmatch(out);
        case 3 || 4 when pairs.isNotEmpty:
          // One side read again: only its account is marked.
          final (out, into) = pairs[r.nextInt(pairs.length)];
          final side = r.nextBool() ? out : into;
          changedSides++;
          await (db.update(
            db.transactions,
          )..where((t) => t.id.equals(side))).write(
            TransactionsCompanion(
              amountMinor: Value((r.nextInt(40) + 5) * 10000),
            ),
          );
        case 5:
          await balances.setBalance(
            accounts[r.nextInt(3)],
            statedMinor: r.nextInt(500) * 1000,
            differenceMinor: (r.nextInt(20) - 10) * 1000,
            at: at,
            currency: 'KES',
          );
        case _:
          await transactions.add(move(accounts[r.nextInt(3)], 15000));
      }
      await journal.sync();
    }
    expect(matched, greaterThan(5));
    expect(changedSides, greaterThan(5));
    final incremental = await journal.balances();
    final rebuilt = await journal.rebuild();
    expect(rebuilt.changed, isFalse, reason: '$rebuilt');
    expect(await journal.balances(), incremental);
    expect(await journal.unbalanced(), isEmpty);
    // Every pair met in one currency, and nothing was named: none of it is
    // still in transit.
    expect(incremental[(BookAccount.moneyInTransit, 'KES')] ?? 0, 0);
  });

  test('a reported balance the records do not reach sits in Not yet sorted '
      'until the person confirms a correction', () async {
    final balances = DriftBalancesRepository(db);
    final mpesa = await account('M-Pesa', AccountType.mpesa, balance: 100000);
    Future<int> pay(int day, int amount, int balance) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            occurredAt: DateTime.utc(2026, 11, day, 9),
            amountMinor: amount,
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.till),
            source: TransactionSource.sms,
            balanceAfterMinor: Value(balance),
          ),
        );
    await pay(2, 10000, 90000);
    // 5,000 short: a message never came.
    await pay(4, 10000, 75000);
    Future<int> of(BookAccount a) async =>
        (await journal.read()).balanceOf(a, currency: 'KES');
    expect(await of(BookAccount.money(mpesa)), 75000);
    // Money that went out with nothing to say where: a debit to sort.
    expect(await of(BookAccount.notYetSorted), -5000);
    expect(await journal.openGaps(), {mpesa: -5000});

    await balances.addGapCorrection(
      mpesa,
      differenceMinor: -5000,
      at: DateTime.utc(2026, 11, 4, 8),
      currency: 'KES',
    );
    expect(await of(BookAccount.money(mpesa)), 75000);
    expect(await of(BookAccount.notYetSorted), 0);
    expect(await of(BookAccount.balanceCorrections), -5000);
    expect(await journal.openGaps(), isEmpty);
  });
}
