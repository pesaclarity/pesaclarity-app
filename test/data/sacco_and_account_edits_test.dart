import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/account_edits.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/message_reads_repository.dart';
import 'package:pesaclarity/src/data/repositories/sacco_links.dart';
import 'package:pesaclarity/src/data/repositories/sacco_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

// Made-up SACCO, paybill, accounts, receipts and amounts.

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late SaccoRepository saccos;
  late AccountEdits edits;
  late JournalRepository journal;
  late int mpesa;
  var receipts = 0;

  final added = eat(2026, 11, 1, 9);

  TransactionsCompanion paidSacco(DateTime at, int shillings) {
    final receipt = 'TSA${(++receipts).toString().padLeft(7, '0')}';
    return TransactionsCompanion.insert(
      accountId: mpesa,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.outflow,
      kind: const Value(TransactionKind.paybill),
      counterpartyKind: const Value(PayeeIdentifierKind.paybill),
      counterpartyValue: Value(
        PayeeIdentifier.paybill('MWANGAZA SACCO', '1234')!.value,
      ),
      counterpartyName: const Value('MWANGAZA SACCO'),
      receiptNo: Value(receipt),
      source: TransactionSource.sms,
      messageHash: Value('hash-$receipt'),
      dedupeKey: Value('$receipt|${kes(shillings)}'),
    );
  }

  Future<int> held(int accountId) async {
    await journal.sync();
    return (await journal.balances())[(BookAccount.money(accountId), 'KES')] ??
        0;
  }

  Future<List<TransactionRecord>> rowsOn(int accountId) => (db.select(
    db.transactions,
  )..where((t) => t.accountId.equals(accountId))).get();

  Future<int> owed(int debtId, CalendarDate today) async =>
      (await DriftDebtsRepository(db).debts(today: today))
          .firstWhere((d) => d.id == debtId)
          .balanceMinor;

  setUp(() async {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    saccos = SaccoRepository(db);
    edits = AccountEdits(db);
    journal = JournalRepository(db, clock: () => eat(2026, 12, 1));
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 1, 1),
            openingBalanceMinor: Value(kes(50000)),
            institutionId: const Value('mpesa'),
          ),
        );
  });

  tearDown(() => db.close());

  test('splits a payment: deposit first, then the loan', () {
    expect(
      splitSaccoPayment(
        kes(9500),
        contributionMinor: kes(3000),
        instalmentMinor: kes(6500),
      ),
      (depositMinor: kes(3000), loanMinor: kes(6500)),
    );
    expect(
      splitSaccoPayment(
        kes(3000),
        contributionMinor: kes(3000),
        instalmentMinor: kes(6500),
      ),
      (depositMinor: kes(3000), loanMinor: 0),
    );
    expect(
      splitSaccoPayment(
        kes(12000),
        contributionMinor: kes(3000),
        instalmentMinor: kes(6500),
      ),
      (depositMinor: kes(5500), loanMinor: kes(6500)),
    );
    expect(saccoNameKey('Mwangaza SACCO Ltd.'), 'mwangaza');
    expect(saccoNameKey('Mwangaza Sacco loan'), 'mwangaza');
  });

  test('check-off paydays, a short month taking its last day', () {
    expect(
      checkOffDays(
        day: 31,
        from: CalendarDate(2026, 10, 15),
        today: CalendarDate(2026, 12, 1),
      ),
      [CalendarDate(2026, 10, 31), CalendarDate(2026, 11, 30)],
    );
    expect(
      nextCheckOff(28, CalendarDate(2026, 11, 22)),
      CalendarDate(2026, 11, 28),
    );
  });

  test('paybill payments move to the SACCO; the loan part repays the loan; '
      'the journal balances', () async {
    final id = await saccos.add(
      name: 'Mwangaza SACCO',
      currency: 'KES',
      paybill: '400 222',
      depositsMinor: kes(84000),
      sharesMinor: kes(20000),
      contributionMinor: kes(3000),
      at: added,
      loan: SaccoLoanInput(
        owedMinor: kes(150000),
        monthlyMinor: kes(6500),
        rateBasisPoints: 1200,
        checkOff: false,
      ),
    );
    final before = paidSacco(eat(2026, 10, 20), 3000);
    await transactions.addNew([before, paidSacco(eat(2026, 11, 19), 9500)]);

    final on = await rowsOn(id);
    final mirror = on.singleWhere(
      (r) => r.direction == TransactionDirection.inflow,
    );
    final loanPart = on.singleWhere((r) => r.debtId != null);
    expect(mirror.amountMinor, kes(9500));
    expect(loanPart.amountMinor, kes(6500));
    final payment = (await rowsOn(mpesa))
        .singleWhere((r) => r.amountMinor == kes(9500));
    expect(payment.transferPairId, mirror.id);
    // Before the SACCO was added, its deposits already hold it.
    expect(
      (await rowsOn(mpesa))
          .singleWhere((r) => r.amountMinor == kes(3000))
          .transferPairId,
      isNull,
    );

    expect(await held(id), kes(84000 + 20000 + 3000));
    expect(await journal.unbalanced(), isEmpty);
    final details = (await saccoDetailsOf(db, id))!;
    expect(
      await owed(details.loanDebtId!, CalendarDate(2026, 11, 22)),
      kes(150000 - 6500),
    );

    // Running it again changes nothing.
    await syncSaccos(db);
    expect((await rowsOn(id)).length, 2);

    // The person unmatched it: it stays as it is, and its mirror goes.
    await transactions.unmatch(payment.id);
    await syncSaccos(db);
    await syncSaccos(db);
    expect(await rowsOn(id), isEmpty);
  });

  test('a check-off loan is taken off each payday, once', () async {
    final id = await saccos.add(
      name: 'Mwangaza SACCO',
      currency: 'KES',
      depositsMinor: kes(84000),
      sharesMinor: 0,
      at: eat(2026, 9, 20, 9),
      loan: SaccoLoanInput(
        owedMinor: kes(10000),
        monthlyMinor: kes(6500),
        checkOffDay: 28,
      ),
    );
    final debtId = (await saccoDetailsOf(db, id))!.loanDebtId!;
    final today = CalendarDate(2026, 11, 22);
    await takeCheckOffs(db, today);
    await takeCheckOffs(db, today);
    final payments = await db.select(db.loanPayments).get();
    // 28 Sep and 28 Oct: the second takes only what was left.
    expect([for (final p in payments) p.amountMinor], [kes(6500), kes(3500)]);
    expect(await owed(debtId, today), 0);
  });

  test('merges SACCO accounts and Sacco loans once', () async {
    final sacco = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Mwangaza Sacco',
            type: AccountType.sacco,
            openingDate: eat(2026, 1, 1),
          ),
        );
    final matched = await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: 'Mwangaza SACCO Ltd',
            type: DebtType.saccoLoan,
            startingBalanceMinor: kes(20000),
          ),
        );
    final alone = await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: 'Ukulima Sacco loan',
            type: DebtType.saccoLoan,
            startingBalanceMinor: kes(5000),
          ),
        );
    await mergeSaccos(db, added);
    await mergeSaccos(db, added);
    final details = await db.select(db.saccoDetails).get();
    expect(details, hasLength(2));
    expect(
      details.singleWhere((d) => d.accountId == sacco).loanDebtId,
      matched,
    );
    final made = details.singleWhere((d) => d.loanDebtId == alone);
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(made.accountId))).getSingle();
    expect(account.name, 'Ukulima Sacco');
    expect(account.type, AccountType.sacco);
    expect(await db.select(db.accounts).get(), hasLength(3));
  });

  group('removing an account', () {
    late int cash;
    late int bank;

    setUp(() async {
      cash = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Cash',
              type: AccountType.cash,
              openingDate: eat(2026, 1, 1),
              openingBalanceMinor: Value(kes(3500)),
            ),
          );
      bank = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Old bank',
              type: AccountType.bank,
              openingDate: eat(2026, 1, 1),
              openingBalanceMinor: Value(kes(8000)),
            ),
          );
    });

    Future<int> typed(
      int account,
      int shillings,
      TransactionDirection direction, {
      String? hash,
    }) => transactions.add(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: eat(2026, 3, 1),
        amountMinor: kes(shillings),
        direction: direction,
        source: TransactionSource.manual,
        messageHash: Value(hash),
      ),
    );

    test('delete: transactions go, their messages are set aside and the '
        'other side of a transfer counts as it was', () async {
      final spent = await typed(
        bank,
        1000,
        TransactionDirection.outflow,
        hash: 'hash-bank-1',
      );
      final out = await typed(bank, 2000, TransactionDirection.outflow);
      final into = await typed(cash, 2000, TransactionDirection.inflow);
      await transactions.match(out, into);
      expect(await edits.transactionCount(bank), 2);
      await held(bank);

      await edits.delete(bank);

      expect(
        await (db.select(
          db.accounts,
        )..where((a) => a.id.equals(bank))).getSingleOrNull(),
        isNull,
      );
      final cashRow = (await rowsOn(cash)).single;
      expect(cashRow.transferPairId, isNull);
      expect(cashRow.transferAccountId, isNull);
      expect(spent, isPositive);
      expect(await MessageReadsRepository(db).setAside({'hash-bank-1'}), {
        'hash-bank-1',
      });
      expect(await held(cash), kes(3500 + 2000));
      expect(await held(bank), 0);
      expect(await journal.unbalanced(), isEmpty);
    });

    test('move: transactions join the account picked; a transfer between '
        'the two goes; totals stay the same', () async {
      await typed(bank, 1000, TransactionDirection.outflow);
      final out = await typed(bank, 2000, TransactionDirection.outflow);
      final into = await typed(cash, 2000, TransactionDirection.inflow);
      await transactions.match(out, into);
      final waits = await typed(mpesa, 500, TransactionDirection.outflow);
      await transactions.setTransferAccount(waits, bank);
      await held(cash);

      await edits.moveAndRemove(bank, cash);

      final onCash = await rowsOn(cash);
      expect(onCash.map((r) => r.amountMinor), [kes(1000)]);
      expect(
        (await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(waits))).getSingle()).transferAccountId,
        cash,
      );
      expect(await held(cash), kes(3500 - 1000));
      expect(await journal.unbalanced(), isEmpty);
    });

    test('a message-read account is never removed', () async {
      expect(() => edits.delete(mpesa), throwsStateError);
    });

    test('saves name, type, last digits, hidden and On hand', () async {
      await edits.save(
        bank,
        name: 'KCB',
        type: AccountType.sacco,
        lastDigits: '43 21',
        hidden: true,
        countsOnHand: true,
        setCountsOnHand: true,
      );
      final a = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(bank))).getSingle();
      expect(a.name, 'KCB');
      expect(a.type, AccountType.sacco);
      expect(a.reference, '***4321');
      expect(a.hidden, isTrue);
      expect(a.countsOnHand, isTrue);
      expect(await saccoDetailsOf(db, bank), isNotNull);
      await edits.save(mpesa, name: 'Equity salary', type: AccountType.cash);
      final m = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(mpesa))).getSingle();
      expect(m.name, 'Equity salary');
      expect(m.type, AccountType.mpesa);
    });
  });
}
