import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/savings_links.dart';
import 'package:pesaclarity/src/data/repositories/savings_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/savings/savings_account.dart';
import 'package:pesaclarity/src/domain/savings/savings_product.dart';
import 'package:pesaclarity/src/domain/savings/savings_prompt.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

// A made-up saver: the paybill's name is public, the account codes,
// receipts, amounts and dates are invented.

const _nabo = 'NABO CAPITAL LTD C2B';

/// The same instant as [expected]: the database hands times back in the
/// phone's own zone.
Matcher _moment(DateTime expected) => predicate<DateTime?>(
  (d) => d != null && d.isAtSameMomentAs(expected),
  'the moment $expected',
);

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftSavingsRepository savings;
  late JournalRepository journal;
  late int mpesa;
  var receipts = 0;

  final today = eat(2026, 11, 21, 9, 41);
  final typedAt = eat(2026, 11, 21, 10);
  final lockedUntil = CalendarDate(2026, 12, 15);

  /// A payment to the Nabo Capital paybill for the account [code].
  TransactionsCompanion paid(
    DateTime at,
    int shillings, {
    String? code = 'CH12345',
    String name = _nabo,
    int fee = 0,
    String currency = 'KES',
    int? account,
  }) {
    final receipt = 'TKA${(++receipts).toString().padLeft(7, '0')}';
    return TransactionsCompanion.insert(
      accountId: account ?? mpesa,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.paybill),
      feeMinor: Value(kes(fee)),
      currency: Value(currency),
      counterpartyKind: const Value(PayeeIdentifierKind.paybill),
      counterpartyValue: Value(PayeeIdentifier.paybill(name, code)!.value),
      counterpartyName: Value(name),
      receiptNo: Value(receipt),
      source: TransactionSource.sms,
      messageHash: Value('hash-$receipt'),
      dedupeKey: Value('$receipt|${kes(shillings)}'),
    );
  }

  /// Money received from [from], as M-Pesa words money back.
  TransactionsCompanion received(
    DateTime at,
    int shillings, {
    String from = 'NABO CAPITAL LTD',
  }) {
    final receipt = 'TKB${(++receipts).toString().padLeft(7, '0')}';
    return TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.inflow,
      kind: const Value(TransactionKind.received),
      counterpartyName: Value(from),
      receiptNo: Value(receipt),
      source: TransactionSource.sms,
      messageHash: Value('hash-$receipt'),
      dedupeKey: Value('$receipt|${kes(shillings)}'),
    );
  }

  /// What the story starts from: five payments under two account codes,
  /// one with a fee, and money back, all read before Chumz was added.
  Future<void> history() async {
    await transactions.addNew([
      paid(eat(2026, 8, 5), 1000),
      paid(eat(2026, 9, 5), 2065, fee: 10),
      paid(eat(2026, 9, 12), 1000, code: 'CH67890'),
      paid(eat(2026, 10, 2), 1500, code: 'CH67890'),
      received(eat(2026, 11, 10), 1000),
      paid(today, 50),
    ]);
  }

  const drafts = [
    SavingsPocketDraft(code: 'CH12345', name: 'Christmas'),
    SavingsPocketDraft(code: 'CH67890', name: 'School fees'),
  ];

  /// Adds Chumz as the Add sheet would: both goals named, Christmas locked.
  Future<SavingsAdded> addChumz({int? prompted}) => savings.add(
    chumz,
    at: today,
    pockets: [
      SavingsPocketDraft(
        code: 'CH12345',
        name: 'Christmas',
        lockedUntil: lockedUntil.startInstant,
      ),
      drafts[1],
    ],
    promptedTransactionId: prompted,
  );

  Future<List<TransactionRecord>> rowsOn(int accountId) =>
      (db.select(db.transactions)
            ..where((t) => t.accountId.equals(accountId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.occurredAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<TransactionRecord> row(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<List<LedgerEntry>> entries() => transactions.ledgerEntries(
    from: DateTime.utc(2026),
    to: DateTime.utc(2027),
  );

  Future<LedgerTotals> totals() async => LedgerTotals.of(
    await entries(),
    from: DateTime.utc(2026),
    to: DateTime.utc(2027),
    currency: 'KES',
  );

  Future<int> held(BookAccount account, {DateTime? at}) async =>
      (await journal.balances(at: at))[(account, 'KES')] ?? 0;

  Future<SavingsAccountSummary> summary() async =>
      (await savings.accounts()).single;

  Future<int> pocketId(String code) async => (await (db.select(
    db.savingsPockets,
  )..where((p) => p.code.equals(code))).getSingle()).id;

  setUp(() async {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    savings = DriftSavingsRepository(db);
    addTearDown(savings.dispose);
    journal = JournalRepository(db);
    receipts = 0;
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 7, 1),
            institutionId: const Value('mpesa'),
          ),
        );
  });

  group('before it is added', () {
    test('payments are spending and money back is money in', () async {
      await history();
      final all = await entries();
      expect(all, hasLength(6));
      expect(all.where((e) => e.isOutflow).map(roleOf).toSet(), {
        LedgerRole.spending,
      });
      expect(
        roleOf(all.singleWhere((e) => e.isInflow)),
        LedgerRole.awaitingPayee,
      );
      final sums = await totals();
      expect(sums.spendingMinor, kes(5615));
      expect(sums.savingMinor, 0);
      expect(await db.select(db.savingsEntries).get(), isEmpty);
    });

    test('discover finds the codes and what adding would link', () async {
      await history();
      await transactions.addNew([
        // Other payees, a near name and the wrong kind of payment.
        paid(eat(2026, 10, 3), 900, name: 'EXAMPLE POWER LTD', code: '77'),
        paid(eat(2026, 10, 4), 300, name: 'NABO CAPITALS LTD'),
        received(eat(2026, 10, 5), 700, from: 'JANE DOE'),
      ]);
      final found = await savings.discover(chumz);
      expect(found.product, same(chumz));
      expect(found.found, isTrue);
      expect(found.payments, 5);
      expect(found.moneyBack, 1);
      expect(found.paidInMinor, kes(5615));
      expect(found.takenOutMinor, kes(1000));
      expect(found.skipped, 0);
      expect(found.firstAt, _moment(eat(2026, 8, 5)));
      final [christmas, school] = found.codes;
      expect(christmas.code, 'CH12345');
      expect(christmas.payments, 3);
      expect(christmas.paidInMinor, kes(3115));
      expect(christmas.firstAt, _moment(eat(2026, 8, 5)));
      expect(christmas.lastAt, _moment(today));
      expect(school.code, 'CH67890');
      expect(school.payments, 2);
      expect(school.paidInMinor, kes(2500));

      // The question goes under the newest payment in.
      final ask = found.latestPayIn!;
      final newest = (await rowsOn(mpesa)).last;
      expect(ask.transactionId, newest.id);
      expect(ask.accountId, mpesa);
      expect(ask.at, _moment(today));
      expect(ask.amountMinor, kes(50));
      expect(ask.currency, 'KES');
      expect(ask.paidTo, 'NABO CAPITAL LTD');
      expect(ask.code, 'CH12345');
      expect((await savings.prompt())!.transactionId, newest.id);
      // Looking changes nothing.
      expect(await db.select(db.savingsPockets).get(), isEmpty);
      expect(
        (await rowsOn(mpesa)).every((r) => r.transferPairId == null),
        isTrue,
      );
    });

    test('with no payments there is nothing to ask', () async {
      await transactions.addNew([
        paid(eat(2026, 10, 3), 900, name: 'EXAMPLE POWER LTD', code: '77'),
      ]);
      final found = await savings.discover(chumz);
      expect(found.found, isFalse);
      expect(found.codes, isEmpty);
      expect(found.latestPayIn, isNull);
      expect(await savings.prompt(), isNull);
    });

    test('money back alone is not asked about', () async {
      await transactions.addNew([received(eat(2026, 11, 10), 1000)]);
      final found = await savings.discover(chumz);
      expect(found.moneyBack, 1);
      expect(found.latestPayIn, isNull);
      expect(await savings.prompt(), isNull);
    });

    test('"It\'s not mine" stops the question and changes nothing', () async {
      await history();
      expect(await savings.declined(), isEmpty);
      await savings.decline('chumz');
      await savings.decline('chumz');
      expect(await savings.declined(), {'chumz'});
      expect(await savings.prompt(), isNull);
      // Still there to add from My accounts.
      expect((await savings.discover(chumz)).payments, 5);
      expect((await totals()).spendingMinor, kes(5615));
      expect(await savings.accounts(), isEmpty);
    });
  });

  group('add', () {
    test('makes the account and turns the payments into transfers', () async {
      await history();
      final wallet = await rowsOn(mpesa);
      final added = await addChumz(prompted: wallet.last.id);
      expect(added.linked, 6);
      expect(added.skipped, 0);

      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(added.accountId))).getSingle();
      expect(account.name, 'Chumz');
      expect(account.type, AccountType.moneyMarket);
      expect(account.product, 'chumz');
      expect(account.institutionId, isNull);
      expect(account.currency, 'KES');
      expect(account.openingBalanceMinor, 0);
      // It opens with the first payment found.
      expect(account.openingDate, _moment(eat(2026, 8, 5)));

      final mirrors = await rowsOn(account.id);
      expect(mirrors, hasLength(6));
      final paidRows = await rowsOn(mpesa);
      for (final payment in paidRows) {
        final mirror = mirrors.singleWhere(
          (m) => m.transferPairId == payment.id,
        );
        expect(payment.transferPairId, mirror.id);
        expect(payment.transferAccountId, account.id);
        expect(mirror.transferAccountId, mpesa);
        expect(mirror.occurredAt, _moment(payment.occurredAt));
        expect(mirror.amountMinor, payment.amountMinor);
        expect(mirror.currency, payment.currency);
        expect(mirror.direction, isNot(payment.direction));
        expect(mirror.source, TransactionSource.manual);
        expect(mirror.kind, isNull);
        expect(mirror.feeMinor, 0);
        expect(mirror.messageHash, isNull);
        expect(mirror.dedupeKey, isNull);
        expect(mirror.receiptNo, isNull);
        expect(mirror.counterpartyName, isNull);
        expect(mirror.balanceAfterMinor, isNull);
        // The payment itself is as its message had it.
        expect(payment.kind, isNotNull);
        expect(payment.messageHash, isNotNull);
      }
      // The fee stays on the payment.
      expect(paidRows[1].feeMinor, kes(10));

      final all = await entries();
      expect(all, hasLength(12));
      expect(all.map(roleOf).toSet(), {LedgerRole.ownTransfer});
      final sums = await totals();
      expect(sums.spendingMinor, 0);
      expect(sums.incomeMinor, 0);
      expect(sums.awaitingPayeeMinor, 0);
      expect(sums.feesMinor, kes(10));
      // Money moved into savings is saved; money back is neither.
      expect(sums.savingMinor, kes(5615));
      expect(sums.ownTransferMinor, kes(1000));
    });

    test('names the pockets, files each entry and reads the balance', () async {
      await history();
      await addChumz();
      final account = await summary();
      expect(account.name, 'Chumz');
      expect(account.productId, 'chumz');
      expect(account.product, same(chumz));
      expect(account.currency, 'KES');
      final [christmas, school] = account.pockets;
      expect((christmas.code, christmas.name), ('CH12345', 'Christmas'));
      expect(christmas.lockedUntil, lockedUntil);
      expect(christmas.isLockedOn(CalendarDate(2026, 12, 14)), isTrue);
      expect(christmas.isLockedOn(lockedUntil), isFalse);
      expect(christmas.balanceMinor, kes(3115));
      expect(christmas.paidInMinor, kes(3115));
      expect(christmas.balanceSetAt, isNull);
      expect((school.code, school.name), ('CH67890', 'School fees'));
      expect(school.lockedUntil, isNull);
      // The money back came from the only goal open that day.
      expect(school.paidInMinor, kes(2500));
      expect(school.takenOutMinor, kes(1000));
      expect(school.balanceMinor, kes(1500));
      expect(account.ignoredPockets, isEmpty);
      expect(account.hasSeveralPockets, isTrue);
      expect(account.lockedCount(CalendarDate(2026, 11, 21)), 1);
      expect(account.lockedCount(lockedUntil), 0);

      expect(account.putInMinor, kes(5615));
      expect(account.takenOutMinor, kes(1000));
      expect(account.interestMinor, 0);
      expect(account.wasThereBeforeMinor, 0);
      expect(account.otherChangesMinor, 0);
      expect(account.balanceMinor, kes(4615));
      expect(account.balanceSetAt, isNull);
      expect(account.unassigned, isEmpty);
      expect(account.updates, isEmpty);

      // Newest first, each with the payment it mirrors.
      expect(account.entries, hasLength(6));
      final newest = account.entries.first;
      expect(newest.kind, SavingsEntryKind.paidIn);
      expect(newest.at, _moment(today));
      expect(newest.amountMinor, kes(50));
      expect(newest.pocketId, christmas.id);
      expect(newest.otherAccountId, mpesa);
      expect(newest.otherTransactionId, (await rowsOn(mpesa)).last.id);
      final back = account.entries[1];
      expect(back.kind, SavingsEntryKind.takenOut);
      expect(back.signedMinor, -kes(1000));
      expect(back.pocketId, school.id);
      expect(await savings.account(account.accountId), isNotNull);
      expect(await savings.account(mpesa), isNull);
    });

    test('keeps the one-time line until it is seen', () async {
      await history();
      expect(await savings.addedNotice(), isNull);
      final prompted = (await rowsOn(mpesa)).last.id;
      final added = await addChumz(prompted: prompted);
      final notice = (await savings.addedNotice())!;
      expect(notice.accountId, added.accountId);
      expect(notice.transactionId, prompted);
      // Five other payments changed with the one asked under.
      expect(notice.updated, 5);
      expect(notice.at, _moment(today));
      expect(notice.seen, isFalse);
      await savings.markAddedNoticeSeen();
      expect(await savings.addedNotice(), isNull);
      await savings.markAddedNoticeSeen();
      expect(await savings.addedNotice(), isNull);
    });

    test('without the question there is no line', () async {
      await history();
      await addChumz();
      expect(await savings.addedNotice(), isNull);
    });

    test('a pocket nobody named is called by its code', () async {
      await history();
      await savings.add(chumz, at: today, name: '  My  Chumz ');
      final account = await summary();
      expect(account.name, 'My Chumz');
      expect(account.pockets.map((p) => p.name), ['CH12345', 'CH67890']);
    });

    test('with no payments yet it has one pocket, named after it', () async {
      final added = await savings.add(chumz, at: today);
      expect(added.linked, 0);
      final account = await summary();
      final [only] = account.pockets;
      expect((only.code, only.name, only.hasCode), ('', 'Chumz', false));
      expect(account.balanceMinor, 0);
      expect(account.hasSeveralPockets, isFalse);
      final row = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(added.accountId))).getSingle();
      expect(row.openingDate, _moment(today));

      // Its first payment gives the pocket its code; a second code is a
      // second pocket.
      await transactions.addNew([paid(eat(2026, 11, 22), 400)]);
      var pockets = (await summary()).pockets;
      expect(pockets.map((p) => (p.code, p.name)), [('CH12345', 'Chumz')]);
      expect(pockets.single.id, only.id);
      expect(pockets.single.balanceMinor, kes(400));
      await transactions.addNew([
        paid(eat(2026, 11, 23), 100, code: 'CH67890'),
      ]);
      pockets = (await summary()).pockets;
      expect(pockets.map((p) => (p.code, p.name)), [
        ('CH12345', 'Chumz'),
        ('CH67890', 'CH67890'),
      ]);
    });

    test('adding it again changes nothing', () async {
      await history();
      final first = await addChumz();
      final again = await savings.add(chumz, at: eat(2026, 11, 22), name: 'X');
      expect(again.accountId, first.accountId);
      expect(again.linked, 0);
      expect((await summary()).name, 'Chumz');
      expect(await rowsOn(first.accountId), hasLength(6));
    });

    test('forgets that it was said to be not theirs', () async {
      await history();
      await savings.decline('chumz');
      await addChumz();
      expect(await savings.declined(), isEmpty);
      // It is there, so there is nothing to ask either way.
      expect(await savings.prompt(), isNull);
    });

    test(
      'leaves alone what the person matched or is in another currency',
      () async {
        final kcb = await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                name: 'Test Bank',
                type: AccountType.bank,
                openingDate: eat(2026, 7, 1),
              ),
            );
        await history();
        // Said to have gone to the bank account: the person's own word.
        final named = await transactions.add(paid(eat(2026, 10, 20), 800));
        await transactions.setTransferAccount(named, kcb);
        // Matched by hand with money typed on the bank account, days apart.
        final matched = await transactions.add(paid(eat(2026, 10, 22), 600));
        final typed = await transactions.add(
          TransactionsCompanion.insert(
            accountId: kcb,
            occurredAt: eat(2026, 10, 24),
            amountMinor: kes(600),
            direction: TransactionDirection.inflow,
            source: TransactionSource.manual,
          ),
        );
        await transactions.match(matched, typed);
        // Paid in dollars: not money in a shilling account.
        final dollars = await transactions.add(
          paid(eat(2026, 10, 25), 20, currency: 'USD'),
        );

        final found = await savings.discover(chumz);
        expect(found.payments, 5);
        expect(found.skipped, 3);
        expect(found.paidInMinor, kes(5615));

        final added = await addChumz();
        expect(added.linked, 6);
        expect(added.skipped, 3);
        expect((await row(named)).transferAccountId, kcb);
        expect((await row(named)).transferPairId, isNull);
        expect((await row(matched)).transferPairId, typed);
        expect((await row(typed)).transferPairId, matched);
        expect((await row(dollars)).transferPairId, isNull);
        expect((await row(dollars)).transferAccountId, isNull);
        expect(await rowsOn(added.accountId), hasLength(6));
        expect((await summary()).balanceMinor, kes(4615));
      },
    );

    test('undoes a pair that pairing made with something unrelated', () async {
      final kcb = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Test Bank',
              type: AccountType.bank,
              openingDate: eat(2026, 7, 1),
            ),
          );
      // Money into the bank the minute the paybill was paid: pairing takes
      // the two for one transfer.
      await transactions.addNew([
        paid(eat(2026, 10, 2, 9), 1500, code: 'CH67890'),
        TransactionsCompanion.insert(
          accountId: kcb,
          occurredAt: eat(2026, 10, 2, 9, 5),
          amountMinor: kes(1500),
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.bank),
          source: TransactionSource.sms,
          messageHash: const Value('hash-bank-credit'),
        ),
      ]);
      final payment = (await rowsOn(mpesa)).single;
      final credit = (await rowsOn(kcb)).single;
      expect(payment.transferPairId, credit.id);

      final added = await savings.add(chumz, at: today);
      expect(added.linked, 1);
      expect(added.skipped, 0);
      final linked = await row(payment.id);
      final mirror = (await rowsOn(added.accountId)).single;
      expect(linked.transferPairId, mirror.id);
      expect(linked.transferAccountId, added.accountId);
      // The bank credit is money in again, and pairing leaves it be.
      expect((await row(credit.id)).transferPairId, isNull);
      expect(await transactions.declinedTransfers(), hasLength(1));
      await transactions.pairOwnTransfers();
      expect((await row(credit.id)).transferPairId, isNull);
      expect((await row(payment.id)).transferPairId, mirror.id);
    });
  });

  group('the books', () {
    test('nothing is ever left on its way between the accounts', () async {
      await history();
      final added = await addChumz();
      final chumzMoney = BookAccount.money(added.accountId);
      // After each payment, in transit is nothing and Chumz holds the sum.
      final moments = <(DateTime, int)>[
        (eat(2026, 8, 5), 0),
        (eat(2026, 8, 6), 1000),
        (eat(2026, 9, 6), 3065),
        (eat(2026, 10, 3), 5565),
        (eat(2026, 11, 11), 4565),
        (eat(2026, 11, 22), 4615),
      ];
      for (final (at, shillings) in moments) {
        await journal.sync();
        expect(
          await held(BookAccount.moneyInTransit, at: at),
          0,
          reason: 'in transit before $at',
        );
        expect(await held(chumzMoney, at: at), kes(shillings), reason: '$at');
      }
      expect(await held(BookAccount.moneyInTransit), 0);
      expect(await journal.unbalanced(), isEmpty);
      expect(await journal.openGaps(), isEmpty);
      // The fixed Savings account of payments to a savings payee is not
      // used: the money is in an account of the person's own.
      expect(await held(BookAccount.savings), 0);
    });

    test('the account holds its pockets and what is in none', () async {
      await history();
      final added = await addChumz();
      final money = BookAccount.money(added.accountId);

      Future<void> agrees() async {
        final account = await summary();
        await journal.sync();
        final pockets = account.pockets.fold(0, (s, p) => s + p.balanceMinor);
        final loose = account.unassigned.fold(0, (s, e) => s + e.signedMinor);
        expect(account.balanceMinor, pockets + loose);
        expect(await held(money), account.balanceMinor);
        expect(
          account.putInMinor -
              account.takenOutMinor +
              account.interestMinor +
              account.wasThereBeforeMinor +
              account.otherChangesMinor,
          account.balanceMinor,
        );
        expect(await held(BookAccount.moneyInTransit), 0);
        expect(await journal.unbalanced(), isEmpty);
      }

      await agrees();
      expect((await summary()).balanceMinor, kes(4615));

      // Balances typed: interest on one goal, nothing on the other.
      await savings.updateBalances(
        added.accountId,
        balanceByPocket: {
          await pocketId('CH12345'): kes(3200),
          await pocketId('CH67890'): kes(1500),
        },
        at: typedAt,
      );
      await agrees();
      expect((await summary()).balanceMinor, kes(4700));

      // Money taken out while both goals were open is in no pocket yet.
      await transactions.addNew([received(eat(2026, 12, 20), 300)]);
      final account = await summary();
      expect(account.unassigned.single.signedMinor, -kes(300));
      expect(account.balanceMinor, kes(4400));
      await agrees();

      // A payment that turns up later, dated before the balances.
      await transactions.addNew([paid(eat(2026, 7, 20), 40)]);
      await agrees();
      expect((await summary()).balanceMinor, kes(4400));
    });
  });

  group('keeping in step', () {
    test('a new payment is linked as it arrives', () async {
      await history();
      final added = await addChumz();
      await transactions.addNew([
        paid(eat(2026, 11, 25), 250, code: 'CH67890'),
        received(eat(2026, 11, 26), 100),
      ]);
      final account = await summary();
      expect(account.entries, hasLength(8));
      expect(
        account.pocket(await pocketId('CH67890'))!.balanceMinor,
        kes(1650),
      );
      final wallet = await rowsOn(mpesa);
      expect(
        wallet.every((r) => r.transferAccountId == added.accountId),
        isTrue,
      );
      expect((await entries()).map(roleOf).toSet(), {LedgerRole.ownTransfer});
      // Other payments are untouched.
      await transactions.addNew([
        paid(eat(2026, 11, 27), 900, name: 'EXAMPLE POWER LTD', code: '77'),
      ]);
      expect((await rowsOn(mpesa)).last.transferPairId, isNull);
      expect((await summary()).entries, hasLength(8));
    });

    test('a new code is a new pocket, named after it', () async {
      await history();
      await addChumz();
      await transactions.addNew([
        paid(eat(2026, 11, 25), 700, code: 'CH24680'),
      ]);
      final pockets = (await summary()).pockets;
      expect(pockets.map((p) => p.name), [
        'Christmas',
        'School fees',
        'CH24680',
      ]);
      expect(pockets.last.balanceMinor, kes(700));
    });

    test('a payment with no code is in no pocket, or the only one', () async {
      await history();
      await addChumz();
      await transactions.addNew([paid(eat(2026, 11, 25), 70, code: null)]);
      final account = await summary();
      expect(account.unassigned.single.amountMinor, kes(70));
      expect(account.balanceMinor, kes(4685));
      // No pocket was made for it.
      expect(account.pockets, hasLength(2));
    });

    test('running it again changes nothing', () async {
      await history();
      final added = await addChumz();
      await savings.updateBalances(
        added.accountId,
        balanceByPocket: {await pocketId('CH12345'): kes(3200)},
        at: typedAt,
      );
      await journal.sync();
      final before = await db.select(db.transactions).get();
      final entriesBefore = await db.select(db.savingsEntries).get();

      for (var i = 0; i < 2; i++) {
        final again = await syncSavingsAccounts(db);
        expect(again.changed, isFalse);
        expect(again.linked, isEmpty);
        expect((again.refreshed, again.removed, again.skipped), (0, 0, 0));
      }
      expect(await db.select(db.transactions).get(), before);
      expect(await db.select(db.savingsEntries).get(), entriesBefore);
      expect(await db.select(db.journalDirty).get(), isEmpty);
      expect((await journal.sync()).changed, isFalse);
      expect(
        (await syncSavingsAccounts(db, accountId: added.accountId)).changed,
        isFalse,
      );
      expect(
        (await syncSavingsAccounts(db, accountId: mpesa)).changed,
        isFalse,
      );
    });

    test('with no savings account the hooks do nothing', () async {
      await history();
      expect((await syncSavingsAccounts(db)).changed, isFalse);
      expect(
        (await linkSavingsPayments(db, [
          for (final r in await rowsOn(mpesa)) r.id,
        ])).changed,
        isFalse,
      );
      expect(
        (await rowsOn(mpesa)).every((r) => r.transferPairId == null),
        isTrue,
      );
    });

    test('a mirror follows its payment and goes when it does', () async {
      await history();
      final added = await addChumz();
      final payment = (await rowsOn(mpesa)).first;
      // The payment's time and amount change, as a merged message would.
      await (db.update(
        db.transactions,
      )..where((t) => t.id.equals(payment.id))).write(
        TransactionsCompanion(
          occurredAt: Value(eat(2026, 8, 6)),
          amountMinor: Value(kes(1100)),
        ),
      );
      var sync = await syncSavingsAccounts(db);
      expect((sync.refreshed, sync.removed), (1, 0));
      var mirror = await row(payment.transferPairId!);
      expect(mirror.occurredAt, _moment(eat(2026, 8, 6)));
      expect(mirror.amountMinor, kes(1100));
      expect((await summary()).balanceMinor, kes(4715));

      // Its payment removed as a copy of another: the mirror goes too.
      final kept = (await rowsOn(mpesa))[1];
      await DriftBalancesRepository(db).removeCopy(payment.id, keptId: kept.id);
      expect(
        await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(mirror.id))).getSingleOrNull(),
        isNull,
      );
      expect(await rowsOn(added.accountId), hasLength(5));
      expect((await summary()).balanceMinor, kes(3615));
      sync = await syncSavingsAccounts(db);
      expect(sync.changed, isFalse);
      mirror = await row(kept.transferPairId!);
      expect(mirror.transferPairId, kept.id);
    });

    test('a payment moved to another account takes its entry along', () async {
      await history();
      final added = await addChumz();
      final other = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Second line',
              type: AccountType.mpesa,
              openingDate: eat(2026, 7, 1),
            ),
          );
      final payment = (await rowsOn(mpesa)).first;
      final balances = DriftBalancesRepository(db);
      await balances.moveToAccount(payment.id, other);
      final moved = await row(payment.id);
      expect(moved.accountId, other);
      expect(moved.transferAccountId, added.accountId);
      final mirror = await row(moved.transferPairId!);
      expect(mirror.transferAccountId, other);
      expect(mirror.accountId, added.accountId);
      expect((await summary()).balanceMinor, kes(4615));

      // An entry on the savings account does not leave it.
      await balances.moveToAccount(mirror.id, other);
      expect((await row(mirror.id)).accountId, added.accountId);
    });

    test('payments and their entries stay matched', () async {
      await history();
      final added = await addChumz();
      final payment = (await rowsOn(mpesa)).first;
      final mirror = payment.transferPairId!;
      await transactions.unmatch(payment.id);
      await transactions.unmatch(mirror);
      await transactions.setTransferAccount(mirror, mpesa);
      await transactions.setTransferAccount(mirror, null);
      expect((await row(payment.id)).transferPairId, mirror);
      expect((await row(payment.id)).transferAccountId, added.accountId);
      expect((await row(mirror)).transferPairId, payment.id);
      expect((await row(mirror)).transferAccountId, mpesa);
      expect(await transactions.declinedTransfers(), isEmpty);
      expect(await isSavingsLinked(db, payment.id), isTrue);
      expect(await isSavingsLinked(db, mirror), isTrue);
      expect(await isSavingsEntry(db, payment.id), isFalse);
      expect(await isSavingsEntry(db, mirror), isTrue);

      final link = (await savings.entryOf(payment.id))!;
      expect(link.accountId, added.accountId);
      expect(link.entryTransactionId, mirror);
      expect(link.kind, SavingsEntryKind.paidIn);
      expect(link.pocketId, await pocketId('CH12345'));
      expect(link.isDerived, isFalse);
      expect((await savings.entryOf(mirror))!.entryTransactionId, mirror);
      expect(await savings.entryOf(999), isNull);
    });
  });

  group('naming it by hand', () {
    test('writes the other side at once, and unnaming takes it away', () async {
      final added = await savings.add(chumz, at: today);
      // A bank transfer the readers do not know went to Chumz.
      final kcb = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Test Bank',
              type: AccountType.bank,
              openingDate: eat(2026, 7, 1),
            ),
          );
      final sent = await transactions.add(
        TransactionsCompanion.insert(
          accountId: kcb,
          occurredAt: eat(2026, 11, 22),
          amountMinor: kes(2000),
          direction: TransactionDirection.outflow,
          kind: const Value(TransactionKind.bank),
          source: TransactionSource.sms,
          messageHash: const Value('hash-bank-debit'),
        ),
      );
      expect(await savings.entryOf(sent), isNull);
      await transactions.setTransferAccount(sent, added.accountId);
      final named = await row(sent);
      final mirror = await row(named.transferPairId!);
      expect(mirror.accountId, added.accountId);
      expect(mirror.direction, TransactionDirection.inflow);
      expect(mirror.amountMinor, kes(2000));
      expect(mirror.transferAccountId, kcb);
      final account = await summary();
      // In the account's one pocket.
      expect(account.pockets.single.balanceMinor, kes(2000));
      expect(account.unassigned, isEmpty);
      final [out, into] = await entries();
      expect(roleOf(out), LedgerRole.ownTransfer);
      expect(roleOf(into), LedgerRole.ownTransfer);
      expect((await totals()).savingMinor, kes(2000));

      await transactions.setTransferAccount(sent, null);
      expect((await row(sent)).transferPairId, isNull);
      expect(await rowsOn(added.accountId), isEmpty);
      expect((await summary()).balanceMinor, 0);
      expect(roleOf((await entries()).single), LedgerRole.spending);
    });

    test('money typed on the account joins its entries', () async {
      await history();
      final added = await addChumz();
      final typed = await transactions.add(
        TransactionsCompanion.insert(
          accountId: added.accountId,
          occurredAt: eat(2026, 11, 22),
          amountMinor: kes(500),
          direction: TransactionDirection.inflow,
          source: TransactionSource.manual,
          counterpartyName: const Value('Bonus'),
        ),
      );
      var account = await summary();
      final entry = account.unassigned.single;
      expect(entry.transactionId, typed);
      expect(entry.kind, SavingsEntryKind.paidIn);
      expect(entry.otherAccountId, isNull);
      expect(account.putInMinor, kes(6115));
      expect(account.balanceMinor, kes(5115));
      await journal.sync();
      expect(
        await held(BookAccount.money(added.accountId)),
        account.balanceMinor,
      );

      // It stays through a sync, and in the pocket it is given.
      await syncSavingsAccounts(db);
      await savings.assignEntry(typed, await pocketId('CH67890'));
      await syncSavingsAccounts(db);
      account = await summary();
      expect(account.unassigned, isEmpty);
      expect(
        account.pocket(await pocketId('CH67890'))!.balanceMinor,
        kes(2000),
      );
      expect((await row(typed)).counterpartyName, 'Bonus');
    });
  });

  group('a code that is not theirs', () {
    test('goes back to how it was counted, until it is taken back', () async {
      await history();
      final added = await addChumz();
      final school = await pocketId('CH67890');
      final goals = DriftGoalsRepository(db);
      final goal = await goals.add(name: 'Fees', targetMinor: kes(20000));
      await goals.setPocket(goal, school);
      expect((await goals.goals()).single.backing, isNotNull);

      await savings.savePocket(
        school,
        name: 'School fees',
        lockedUntil: null,
        ignored: true,
      );
      var account = await summary();
      expect(account.pockets.map((p) => p.name), ['Christmas']);
      expect(account.ignoredPockets.single.name, 'School fees');
      expect(account.ignoredPockets.single.balanceMinor, 0);
      // Its two payments are spending again; the rest are as they were.
      final wallet = await rowsOn(mpesa);
      final theirs = wallet.where(
        (r) => (r.counterpartyValue ?? '').endsWith('#CH67890'),
      );
      expect(theirs, hasLength(2));
      for (final r in theirs) {
        expect(r.transferPairId, isNull);
        expect(r.transferAccountId, isNull);
      }
      expect((await totals()).spendingMinor, kes(2500));
      expect(await rowsOn(added.accountId), hasLength(4));
      expect(account.putInMinor, kes(3115));
      // A goal cannot be saved in it.
      expect((await goals.goals()).single.backing, isNull);
      // A new payment to it is spending too, and makes no second pocket.
      await transactions.addNew([
        paid(eat(2026, 11, 25), 300, code: 'CH67890'),
      ]);
      expect((await rowsOn(mpesa)).last.transferPairId, isNull);
      expect((await totals()).spendingMinor, kes(2800));
      expect(await db.select(db.savingsPockets).get(), hasLength(2));
      await journal.sync();
      account = await summary();
      expect(
        await held(BookAccount.money(added.accountId)),
        account.balanceMinor,
      );
      expect(await held(BookAccount.moneyInTransit), 0);

      await savings.savePocket(school, name: 'Fees', lockedUntil: null);
      account = await summary();
      expect(account.pockets.map((p) => p.name), ['Christmas', 'Fees']);
      expect(account.ignoredPockets, isEmpty);
      expect((await totals()).spendingMinor, 0);
      expect(account.putInMinor, kes(5915));
      expect(await rowsOn(added.accountId), hasLength(7));
    });
  });

  group('balances the person types', () {
    late int accountId;
    late int christmas;
    late int school;

    setUp(() async {
      await history();
      accountId = (await addChumz()).accountId;
      christmas = await pocketId('CH12345');
      school = await pocketId('CH67890');
    });

    Future<List<(SavingsEntryRow, TransactionRecord)>> derived() async {
      final t = db.transactions;
      final e = db.savingsEntries;
      final rows =
          await (db.select(e).join([
                  innerJoin(t, t.id.equalsExp(e.transactionId)),
                ])
                ..where(
                  e.kind.isInValues([
                    SavingsEntryKind.interest,
                    SavingsEntryKind.correction,
                  ]),
                )
                ..orderBy([
                  OrderingTerm.asc(t.occurredAt),
                  OrderingTerm.asc(t.id),
                ]))
              .get();
      return [for (final r in rows) (r.readTable(e), r.readTable(t))];
    }

    test('show interest: one entry, income under Interest', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200), school: kes(1500)},
        at: typedAt,
      );
      final account = await summary();
      expect(account.balanceMinor, kes(4700));
      expect(account.putInMinor, kes(5615));
      expect(account.takenOutMinor, kes(1000));
      expect(account.interestMinor, kes(85));
      expect(account.wasThereBeforeMinor, 0);
      expect(account.otherChangesMinor, 0);
      expect(account.balanceSetAt, _moment(typedAt));
      expect(account.pocket(christmas)!.balanceMinor, kes(3200));
      expect(account.pocket(christmas)!.interestMinor, kes(85));
      expect(account.pocket(christmas)!.balanceSetAt, _moment(typedAt));
      expect(account.pocket(school)!.balanceMinor, kes(1500));
      final update = account.updates.single;
      expect(update.at, _moment(typedAt));
      expect(update.balanceMinor, kes(4700));
      expect(update.interestMinor, kes(85));
      expect(update.changeMinor, kes(85));
      expect(update.pocketIds, [christmas, school]);

      final [(entry, tx)] = await derived();
      expect(entry.kind, SavingsEntryKind.interest);
      expect(entry.pocketId, isNull);
      expect(tx.accountId, accountId);
      expect(tx.occurredAt, _moment(typedAt));
      expect(tx.amountMinor, kes(85));
      expect(tx.direction, TransactionDirection.inflow);
      expect(tx.source, TransactionSource.manual);
      expect(tx.kind, isNull);
      expect(tx.counterpartyName, 'Chumz interest');
      expect(tx.balanceAfterMinor, isNull);
      final category = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(tx.categoryOverrideId!))).getSingle();
      expect((category.key, category.name), ('interest', 'Interest'));
      expect(category.type, CategoryType.income);

      final entry0 = (await entries()).singleWhere((e) => e.id == tx.id);
      expect(roleOf(entry0), LedgerRole.income);
      expect((await totals()).incomeMinor, kes(85));
      final link = (await savings.entryOf(tx.id))!;
      expect(link.isDerived, isTrue);
      expect(link.readingAt, _moment(typedAt));
    });

    test('an Interest of the person\'s own that is not income stays as it '
        'is', () async {
      final paid = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'interest',
              type: CategoryType.expense,
            ),
          );
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200), school: kes(1500)},
        at: typedAt,
      );
      final [(_, tx)] = await derived();
      final category = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(tx.categoryOverrideId!))).getSingle();
      expect(category.id, isNot(paid));
      expect((category.key, category.name), ('interest', 'Interest earned'));
      expect(category.type, CategoryType.income);
      final own = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(paid))).getSingle();
      expect((own.key, own.type), (null, CategoryType.expense));
      expect((await totals()).incomeMinor, kes(85));
    });

    test('one balance for one goal leaves the others as they are', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200)},
        at: typedAt,
      );
      final account = await summary();
      expect(account.balanceMinor, kes(4700));
      expect(account.pocket(school)!.balanceSetAt, isNull);
      expect(account.updates.single.pocketIds, [christmas]);
    });

    test('typed again at the same time replace what was typed', () async {
      for (final shillings in [3200, 3180]) {
        await savings.updateBalances(
          accountId,
          balanceByPocket: {christmas: kes(shillings)},
          at: typedAt.add(const Duration(milliseconds: 400)),
        );
      }
      expect(await db.select(db.savingsReadings).get(), hasLength(1));
      expect((await summary()).interestMinor, kes(65));
      expect(await derived(), hasLength(1));
    });

    test('a first balance far above the records was there before', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(9000), school: kes(1400)},
        at: typedAt,
      );
      final account = await summary();
      expect(account.interestMinor, 0);
      expect(account.wasThereBeforeMinor, kes(5885));
      expect(account.otherChangesMinor, -kes(100));
      expect(account.balanceMinor, kes(10400));
      // One correction for the update, never income or spending.
      final [(entry, tx)] = await derived();
      expect(entry.kind, SavingsEntryKind.correction);
      expect(tx.kind, TransactionKind.correction);
      expect(tx.direction, TransactionDirection.inflow);
      expect(tx.amountMinor, kes(5785));
      expect(tx.balanceAfterMinor, isNull);
      expect(tx.categoryOverrideId, isNull);
      final sums = await totals();
      expect(sums.incomeMinor, 0);
      expect(sums.spendingMinor, 0);
      await journal.sync();
      expect(await held(BookAccount.money(accountId)), kes(10400));
      expect(await held(BookAccount.balanceCorrections), kes(5785));
    });

    test('interest and a correction can come from one update', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200), school: kes(1400)},
        at: typedAt,
      );
      final rows = await derived();
      expect(rows.map((r) => r.$1.kind).toSet(), {
        SavingsEntryKind.interest,
        SavingsEntryKind.correction,
      });
      final correction = rows.singleWhere(
        (r) => r.$1.kind == SavingsEntryKind.correction,
      );
      expect(correction.$2.direction, TransactionDirection.outflow);
      expect(correction.$2.amountMinor, kes(100));
      final account = await summary();
      expect(account.interestMinor, kes(85));
      expect(account.otherChangesMinor, -kes(100));
      expect(account.balanceMinor, kes(4600));
    });

    test('said not to be interest, a gap is another change', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200)},
        at: typedAt,
        gapIsInterest: false,
      );
      final account = await summary();
      expect(account.interestMinor, 0);
      expect(account.wasThereBeforeMinor, kes(85));
      expect((await derived()).single.$1.kind, SavingsEntryKind.correction);
    });

    test('an older payment found later shrinks the interest', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200)},
        at: typedAt,
      );
      final [(_, before)] = await derived();
      expect(before.amountMinor, kes(85));

      await transactions.addNew([paid(eat(2026, 7, 20), 60)]);
      final [(_, after)] = await derived();
      // The same entry, smaller.
      expect(after.id, before.id);
      expect(after.amountMinor, kes(25));
      final account = await summary();
      expect(account.interestMinor, kes(25));
      expect(account.putInMinor, kes(5675));
      expect(account.balanceMinor, kes(4700));
      // The account now opens with that payment.
      final opened = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(accountId))).getSingle();
      expect(opened.openingDate, _moment(eat(2026, 7, 20)));
      await journal.sync();
      expect(await held(BookAccount.money(accountId)), kes(4700));

      // One that explains all of it leaves no interest entry at all.
      await transactions.addNew([paid(eat(2026, 7, 21), 25)]);
      expect(await derived(), isEmpty);
      expect((await summary()).interestMinor, 0);
    });

    test('money in or out in no pocket has to be placed first', () async {
      // Both goals open by then, so the records cannot say which it left.
      await transactions.addNew([received(eat(2026, 12, 20), 300)]);
      final loose = (await summary()).unassigned.single;
      final later = eat(2026, 12, 21);
      await expectLater(
        savings.updateBalances(
          accountId,
          balanceByPocket: {christmas: kes(2900)},
          at: later,
        ),
        throwsStateError,
      );
      expect(await db.select(db.savingsReadings).get(), isEmpty);
      // A balance from before it can still be typed.
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200)},
        at: typedAt,
      );

      await savings.assignEntry(loose.transactionId, christmas);
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(2910)},
        at: later,
      );
      final account = await summary();
      expect(account.unassigned, isEmpty);
      expect(account.pocket(christmas)!.takenOutMinor, kes(300));
      expect(account.interestMinor, kes(95));
      expect(account.balanceMinor, kes(4410));
      // It can be taken out of the pocket again.
      await savings.assignEntry(loose.transactionId, null);
      expect((await summary()).unassigned, hasLength(1));
    });

    test(
      'refuses a pocket that is not its own and a balance below zero',
      () async {
        await expectLater(
          savings.updateBalances(
            accountId,
            balanceByPocket: {999: kes(1)},
            at: typedAt,
          ),
          throwsArgumentError,
        );
        await expectLater(
          savings.updateBalances(
            accountId,
            balanceByPocket: {christmas: -1},
            at: typedAt,
          ),
          throwsArgumentError,
        );
        await expectLater(
          savings.updateBalances(mpesa, balanceByPocket: const {}, at: typedAt),
          throwsArgumentError,
        );
        expect(await db.select(db.savingsReadings).get(), isEmpty);
      },
    );

    test('a payment under a code stays in that code\'s pocket', () async {
      final coded = (await summary()).entries.first;
      await expectLater(
        savings.assignEntry(coded.transactionId, school),
        throwsArgumentError,
      );
      final back = (await summary()).entries[1];
      await expectLater(
        savings.assignEntry(back.transactionId, 999),
        throwsArgumentError,
      );
      await expectLater(
        savings.assignEntry((await rowsOn(mpesa)).first.id, school),
        throwsArgumentError,
      );
      // Money back can be moved to the goal it really left.
      await savings.assignEntry(back.transactionId, christmas);
      await syncSavingsAccounts(db);
      final account = await summary();
      expect(account.pocket(christmas)!.balanceMinor, kes(2115));
      expect(account.pocket(school)!.balanceMinor, kes(2500));
    });

    test('undoing an update takes its interest and correction away', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200), school: kes(1400)},
        at: typedAt,
      );
      await journal.sync();
      expect(await derived(), hasLength(2));
      await savings.undoUpdate(accountId, typedAt);
      expect(await derived(), isEmpty);
      expect(await db.select(db.savingsReadings).get(), isEmpty);
      final account = await summary();
      expect(account.balanceMinor, kes(4615));
      expect(account.balanceSetAt, isNull);
      expect(account.updates, isEmpty);
      expect((await totals()).incomeMinor, 0);
      await journal.sync();
      expect(await held(BookAccount.money(accountId)), kes(4615));
      expect(await held(BookAccount.balanceCorrections), 0);
      expect(await journal.unbalanced(), isEmpty);
    });

    test('only the update undone goes', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200)},
        at: typedAt,
      );
      final second = eat(2026, 12, 21);
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3240)},
        at: second,
      );
      expect((await summary()).interestMinor, kes(125));
      expect((await summary()).updates.map((u) => u.at), [
        _moment(second),
        _moment(typedAt),
      ]);
      await savings.undoUpdate(accountId, second);
      expect((await summary()).interestMinor, kes(85));
      expect((await summary()).balanceSetAt, _moment(typedAt));
    });

    test('undoing a correction it showed removes that balance', () async {
      await savings.updateBalances(
        accountId,
        balanceByPocket: {christmas: kes(3200), school: kes(1400)},
        at: typedAt,
      );
      final correction = (await derived()).singleWhere(
        (r) => r.$1.kind == SavingsEntryKind.correction,
      );
      final balances = DriftBalancesRepository(db);
      await balances.undoCorrection(correction.$2.id);
      // The update is undone whole: its interest goes with it.
      expect(await derived(), isEmpty);
      expect(await db.select(db.savingsReadings).get(), isEmpty);
      expect((await summary()).balanceMinor, kes(4615));

      // A correction the person made on another account is undone as before.
      final own = await balances.setBalance(
        mpesa,
        statedMinor: kes(100),
        differenceMinor: kes(100),
        at: eat(2026, 11, 22),
        currency: 'KES',
      );
      await balances.undoCorrection(own);
      expect(
        await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(own))).getSingleOrNull(),
        isNull,
      );
      // Anything that is not a correction is left alone.
      final payment = (await rowsOn(mpesa)).first.id;
      await balances.undoCorrection(payment);
      expect((await row(payment)).id, payment);
    });
  });

  group('names', () {
    test('the account and its pockets can be renamed', () async {
      await history();
      final added = await addChumz();
      await savings.rename(added.accountId, ' Rainy day ');
      expect((await summary()).name, 'Rainy day');
      expect((await summary()).product!.provider, 'Nabo Capital');
      await expectLater(
        savings.rename(added.accountId, '  '),
        throwsArgumentError,
      );
      await expectLater(savings.rename(mpesa, 'X'), throwsArgumentError);

      final christmas = await pocketId('CH12345');
      await savings.savePocket(
        christmas,
        name: 'December',
        lockedUntil: CalendarDate(2027, 1, 5).startInstant,
      );
      final pocket = (await summary()).pocket(christmas)!;
      expect(pocket.name, 'December');
      expect(pocket.lockedUntil, CalendarDate(2027, 1, 5));
      await expectLater(
        savings.savePocket(christmas, name: ' ', lockedUntil: null),
        throwsArgumentError,
      );
      await expectLater(
        savings.savePocket(999, name: 'X', lockedUntil: null),
        throwsArgumentError,
      );
    });

    test('a pocket with no code follows the account\'s name', () async {
      final added = await savings.add(chumz, at: today);
      await savings.rename(added.accountId, 'Holiday');
      expect((await summary()).pockets.single.name, 'Holiday');
    });
  });

  group('remove', () {
    test('puts everything back and takes the account away', () async {
      await history();
      final before = await rowsOn(mpesa);
      final categoriesBefore = (await db.select(db.categories).get()).length;
      await journal.sync();
      final spentBefore = await held(BookAccount.uncategorisedSpending);
      final mpesaBefore = await held(BookAccount.money(mpesa));

      final added = await addChumz(prompted: before.last.id);
      final goals = DriftGoalsRepository(db);
      final goal = await goals.add(name: 'Christmas', targetMinor: kes(10000));
      await goals.setPocket(goal, await pocketId('CH12345'));
      await savings.updateBalances(
        added.accountId,
        balanceByPocket: {
          await pocketId('CH12345'): kes(3200),
          await pocketId('CH67890'): kes(1400),
        },
        at: typedAt,
      );
      await journal.sync();
      expect(await held(BookAccount.money(added.accountId)), kes(4600));

      await savings.remove(added.accountId);

      // The payments are as they were read, to the field.
      expect(await rowsOn(mpesa), before);
      expect(await db.select(db.transactions).get(), hasLength(before.length));
      expect(
        await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(added.accountId))).getSingleOrNull(),
        isNull,
      );
      expect(await db.select(db.savingsPockets).get(), isEmpty);
      expect(await db.select(db.savingsEntries).get(), isEmpty);
      expect(await db.select(db.savingsReadings).get(), isEmpty);
      expect(await savings.accounts(), isEmpty);
      expect(await savings.addedNotice(), isNull);
      final sums = await totals();
      expect(sums.spendingMinor, kes(5615));
      expect(sums.awaitingPayeeMinor, kes(1000));
      expect(sums.incomeMinor, 0);
      expect(sums.savingMinor, 0);
      // The goal stays, with what the person had typed for it.
      final kept = (await goals.goals()).single;
      expect(kept.backing, isNull);
      expect(kept.savedMinor, 0);
      // Only the Interest category it made is left behind.
      expect(
        (await db.select(db.categories).get()).length,
        categoriesBefore + 1,
      );

      // The journal has nothing left of the account, and still balances.
      final sync = await journal.sync();
      expect(sync.changed, isTrue);
      expect(await held(BookAccount.money(added.accountId)), 0);
      expect(await held(BookAccount.moneyInTransit), 0);
      expect(await held(BookAccount.balanceCorrections), 0);
      expect(await held(BookAccount.uncategorisedSpending), spentBefore);
      expect(await held(BookAccount.money(mpesa)), mpesaBefore);
      expect(await journal.unbalanced(), isEmpty);
      expect((await journal.sync()).changed, isFalse);
      final rebuilt = await journal.rebuild();
      expect(rebuilt.changed, isFalse);

      // It is not asked about again, but can be added again.
      expect(await savings.declined(), {'chumz'});
      expect(await savings.prompt(), isNull);
      expect((await savings.discover(chumz)).payments, 5);
      final again = await addChumz();
      expect(again.linked, 6);
      expect(await savings.declined(), isEmpty);
      expect((await summary()).balanceMinor, kes(4615));
    });

    test('keeps the account when the person typed entries on it', () async {
      await history();
      final added = await addChumz();
      final typed = await transactions.add(
        TransactionsCompanion.insert(
          accountId: added.accountId,
          occurredAt: eat(2026, 11, 22),
          amountMinor: kes(500),
          direction: TransactionDirection.inflow,
          source: TransactionSource.manual,
        ),
      );
      await savings.remove(added.accountId);
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(added.accountId))).getSingle();
      // An ordinary account now, with only what was typed.
      expect(account.product, isNull);
      expect((await rowsOn(added.accountId)).single.id, typed);
      expect(await db.select(db.savingsEntries).get(), isEmpty);
      expect(await db.select(db.savingsPockets).get(), isEmpty);
      expect(await savings.accounts(), isEmpty);
      expect(
        (await rowsOn(mpesa)).every((r) => r.transferPairId == null),
        isTrue,
      );
      await journal.sync();
      expect(await held(BookAccount.money(added.accountId)), kes(500));
      expect(await held(BookAccount.moneyInTransit), 0);
      expect(await journal.unbalanced(), isEmpty);
    });

    test('refuses an account that is not a savings account', () async {
      await expectLater(savings.remove(mpesa), throwsArgumentError);
      expect(await db.select(db.accounts).get(), hasLength(1));
    });
  });

  test('changes are reported to whoever watches', () async {
    await history();
    final seen = <void>[];
    final watching = savings.watchChanges().listen(seen.add);
    addTearDown(watching.cancel);
    await savings.decline('chumz');
    await pumpEventQueue();
    expect(seen, hasLength(1));
    await addChumz();
    await pumpEventQueue();
    expect(seen.length, greaterThan(1));
    // A goal saved in a pocket shows on the pocket.
    final before = seen.length;
    await DriftGoalsRepository(db).add(name: 'Fees', targetMinor: kes(100));
    await pumpEventQueue();
    expect(seen.length, greaterThan(before));
  });
}
