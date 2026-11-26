// The journal's replay test (decision 0018, stage 5): a messy synthetic
// November for one person, fed message by message through the same reader,
// statement importer and repositories the app uses. It has a message the
// reader cannot read, Fuliza drawn and repaid, money from KCB into M-Pesa
// twice (once with a fee), a statement imported over messages already read
// and then imported again, and a balance the person typed wrongly while
// checking a message. After every step every account must match the
// balances its messages reported; at the end On hand must be the sum the
// person would get by hand, nothing may be left in Not yet sorted or Money
// in transit, and every figure read from the journal (decision 0018,
// stage 4) must add up with the books.
//
// Synthetic data only: invented names, numbers, receipts and amounts.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/review_inbox_repository.dart';
import 'package:pesaclarity/src/data/repositories/statement_imports_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/tags/tag_totals.dart';
import 'package:pesaclarity/src/features/accounts/domain/institution.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';
import 'package:ujumbe/ujumbe.dart' show SmsMessage;

import '../helpers/balance_oracle.dart';
import '../helpers/journal_history.dart';
import '../helpers/statement_samples.dart';
import '../helpers/test_app.dart';

/// A time in East Africa Time, as messages print it.
DateTime _eat(int d, int h, [int min = 0, int s = 5]) =>
    DateTime.utc(2026, 11, d, h - 3, min, s);

SmsMessage _m(String body, DateTime at) =>
    SmsMessage(sender: 'MPESA', body: body, receivedAt: at);
SmsMessage _k(String body, DateTime at) =>
    SmsMessage(sender: 'KCB', body: body, receivedAt: at);

/// Shillings in cents.
int _kes(int shillings, [int cents = 0]) => shillings * 100 + cents;

/// The month, oldest first. Each entry is one message, or a step.
final _month = <Object>[
  _m(
    'TJB1000001 Confirmed.You have received Ksh5,000.00 from JOHN KAMAU '
    '0700***002 on 1/11/26 at 8:00 AM  New M-PESA balance is Ksh15,000.00.',
    _eat(1, 8),
  ),
  _m(
    'TJB1000002 Confirmed. Ksh1,500.00 sent to JANE DOE 0700***001 on '
    '2/11/26 at 9:15 AM. New M-PESA balance is Ksh13,485.00. Transaction '
    'cost, Ksh15.00. Amount you can transact within the day is 498,500.00.',
    _eat(2, 9, 15),
  ),
  // One the reader cannot read: it waits to be checked, and the next
  // balance is KES 500 short until the statement brings its record.
  _m(
    'TJB1000003 Confirmd Ksh500.00 pd to EXAMPLE CHEMIST 3/11/26 10:00 AM '
    'bal Ksh12,985.00 ##',
    _eat(3, 10),
  ),
  _m(
    'TJB1000004 Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on 3/11/26 at '
    '1:45 PM.New M-PESA balance is Ksh12,635.00. Transaction cost, Ksh0.00. '
    'Amount you can transact within the day is 496,950.00.',
    _eat(3, 13, 45),
  ),
  // The statement for 1 to 3 November, over the messages already read:
  // it brings the one the reader could not read. Imported twice.
  #statement,
  #statementAgain,
  // KCB into M-Pesa, the same amount on both sides.
  _k(
    'Dear Customer, KES 3,000.00 has been debited from your account ****0001 '
    'on 05/11/2026 at 10:00. Transaction Ref: KCB1000000101. Your available '
    'balance is KES 17,000.00.',
    _eat(5, 10),
  ),
  _m(
    'TJB1000006 Confirmed.You have received Ksh3,000.00 from EXAMPLE BANK 1 '
    '522522 on 5/11/26 at 10:01 AM New M-PESA balance is Ksh15,635.00.',
    _eat(5, 10, 1),
  ),
  // A KCB message the reader cannot read. The person checks it and types
  // the balance wrong: KES 16,500 for the KES 16,000 it left.
  _k(
    'KCB: ac ****0001 dr KES 1,000.00 08/11/2026 ref KCB1000000102 avl ?',
    _eat(8, 15),
  ),
  #checkWithWrongBalance,
  // KCB into M-Pesa with a fee: KES 2,030 leaves, KES 2,000 arrives.
  _k(
    'Dear Customer, KES 2,030.00 has been debited from your account ****0001 '
    'on 10/11/2026 at 11:00. Transaction Ref: KCB1000000103. Your available '
    'balance is KES 13,970.00.',
    _eat(10, 11),
  ),
  _m(
    'TJB1000008 Confirmed.You have received Ksh2,000.00 from EXAMPLE BANK 1 '
    '522522 on 10/11/26 at 11:01 AM New M-PESA balance is Ksh17,635.00.',
    _eat(10, 11, 1),
  ),
  // Paying KES 18,000 with KES 17,635: Fuliza covers KES 365.
  _m(
    'TJB1000009 Confirmed. Ksh18,000.00 sent to JANE DOE 0700***001 on '
    '15/11/26 at 12:00 PM. New M-PESA balance is Ksh0.00. Transaction cost, '
    'Ksh0.00. Amount you can transact within the day is 480,000.00.',
    _eat(15, 12),
  ),
  _m(
    'TJB1000010 Confirmed. Fuliza M-Pesa amount is Ksh 365.00. Access Fee '
    'charged Ksh 3.65. Total Fuliza M-Pesa outstanding amount is Ksh 368.65 '
    'due on 15/12/26. To check daily charges, Dial *000*0#OK Select Query '
    'Charges',
    _eat(15, 12, 0, 35),
  ),
  // Money in repays Fuliza first: both messages print what is left.
  _m(
    'TJB1000011 Confirmed.You have received Ksh2,000.00 from JOHN KAMAU '
    '0700***002 on 20/11/26 at 8:00 AM  New M-PESA balance is Ksh1,631.35.',
    _eat(20, 8),
  ),
  _m(
    'TJB1000012 Confirmed. Ksh 368.65 from your M-PESA has been used to fully '
    'pay your outstanding Fuliza M-PESA. Available Fuliza M-PESA limit is '
    'Ksh 2,000.00. M-PESA balance is Ksh1,631.35.',
    _eat(20, 8, 0, 20),
  ),
  _m(
    'TJB1000013 Confirmed.on 25/11/26 at 5:10 PMWithdraw Ksh1,000.00 from '
    '123456 - EXAMPLE AGENT SHOP NAIROBI New M-PESA balance is Ksh602.35. '
    'Transaction cost, Ksh29.00.',
    _eat(25, 17, 10),
  ),
  // Money from someone not named is not yet sorted, never income, until
  // the person says what it was: John pays them.
  #sortJohn,
];

/// What the last messages say each account holds.
final _mpesaNow = _kes(602, 35);
final _kcbNow = _kes(13970);

/// The statement's rows for 1 to 3 November, in the same receipts.
const _statementRows = <StatementRowSample>[
  (
    receipt: 'TJB1000001',
    time: '2026-11-01 08:00:05',
    details: 'Funds received from - 0700***002 JOHN KAMAU',
    amount: 500000,
  ),
  (
    receipt: 'TJB1000002',
    time: '2026-11-02 09:15:05',
    details: 'Customer Transfer to - 0700***001 JANE DOE',
    amount: -150000,
  ),
  (
    receipt: 'TJB1000002',
    time: '2026-11-02 09:15:05',
    details: 'Customer Transfer of Funds Charge',
    amount: -1500,
  ),
  (
    receipt: 'TJB1000003',
    time: '2026-11-03 10:00:05',
    details: 'Merchant Payment Online to 5000002 - EXAMPLE CHEMIST',
    amount: -50000,
  ),
  (
    receipt: 'TJB1000004',
    time: '2026-11-03 13:45:05',
    details: 'Merchant Payment Online to 5000001 - EXAMPLE GROCERS',
    amount: -35000,
  ),
];

void main() {
  test('a messy month: every account matches its reported balances after '
      'every message, On hand is the sum by hand, and every figure read '
      'from the journal adds up with the books', () async {
    final db = openTestDatabase();
    final monthEnd = DateTime.utc(2026, 12);
    final journal = JournalRepository(db, clock: () => monthEnd);
    final log = JournalLog(db, journal);
    final accounts = DriftAccountsRepository(db);
    final transactions = DriftTransactionsRepository(db);
    final inbox = DriftReviewInboxRepository(db);
    final selected = [
      for (final id in ['mpesa', 'kcb'])
        institutionCatalogue.singleWhere((i) => i.id == id),
    ];
    final ingestor = SmsIngestor(
      accounts: accounts,
      transactions: transactions,
      reviewInbox: inbox,
      parse: (packs, messages) async => parseAll(packs, messages),
    );
    final importer = StatementImporter(
      extractor: FakePdfTextExtractor({
        'november': mpesaStatementPages(
          rows: _statementRows,
          opening: _kes(10000),
          period: '01 Nov 2026 - 03 Nov 2026',
        ),
      }),
      read: (pages) async => readStatement(pages),
      accounts: accounts,
      transactions: transactions,
      imports: DriftStatementImportsRepository(db),
      institutions: institutionCatalogue,
      now: () => _eat(4, 9),
    );

    Future<Account> account(String institution) async =>
        (await db.select(db.accounts).get()).singleWhere(
          (a) => a.institutionId == institution,
        );

    // After every step: nothing stored was edited, every entry balances,
    // and each account is what the records say, reported balances and all.
    Future<void> check(String step) async {
      await log.check();
      expect(
        await reconcileWithOracle(db, at: monthEnd),
        isEmpty,
        reason: 'after $step',
      );
    }

    var rows = 0;
    for (final step in _month) {
      switch (step) {
        case final SmsMessage message:
          await ingestor.ingest([message], selected);
          await check(message.body.substring(0, 10));
        case #statement:
          final before = (await db.select(db.transactions).get()).length;
          final outcome = await importer.importPdf(fakePdf('november'));
          final summary = (outcome as StatementImported).summary;
          // Only the one the reader could not read is new.
          expect(summary.addedCount, 1);
          expect(summary.gapMinor, 0);
          expect(await db.select(db.transactions).get(), hasLength(before + 1));
          await check('the statement');
        case #statementAgain:
          rows = (await db.select(db.transactions).get()).length;
          final again = await importer.importPdf(fakePdf('november'));
          expect(again, isA<StatementAlreadyImported>());
          expect(await db.select(db.transactions).get(), hasLength(rows));
          await check('the statement again');
        case #checkWithWrongBalance:
          final kcb = await account('kcb');
          await transactions.addNew([
            TransactionsCompanion.insert(
              accountId: kcb.id,
              occurredAt: _eat(8, 15),
              amountMinor: _kes(1000),
              direction: TransactionDirection.outflow,
              kind: const Value(TransactionKind.bank),
              source: TransactionSource.sms,
              receiptNo: const Value('KCB1000000102'),
              dedupeKey: const Value('checked:KCB1000000102'),
              // What the person typed: KES 500 too much.
              claimedBalanceMinor: Value(_kes(16500)),
            ),
          ]);
          await check('the KCB message checked');
        case #sortJohn:
          final income =
              (await (db.select(db.categories)
                        ..where((c) => c.type.equalsValue(CategoryType.income)))
                      .get())
                  .first;
          for (final t in await db.select(db.transactions).get()) {
            if (t.counterpartyName == 'JOHN KAMAU') {
              await DriftCategoriesRepository(db).setOverride(t.id, income.id);
            }
          }
          await check("John's money sorted");
      }
    }

    final mpesa = await account('mpesa');
    final kcb = await account('kcb');

    // Each payment is stored once, whatever read it.
    final stored = await db.select(db.transactions).get();
    expect(
      stored.where((t) => t.receiptNo == 'TJB1000003'),
      hasLength(1),
      reason: 'the statement brought the unread message once',
    );
    expect(stored.length, greaterThanOrEqualTo(rows));

    // Nothing stored was edited; a rebuild changes nothing.
    expect((await journal.rebuild()).changed, isFalse);
    expect(await journal.unbalanced(), isEmpty);

    // Every account matches the balances its messages reported, Fuliza is
    // repaid, and nothing is left waiting.
    expect(await journal.openGaps(), isEmpty);
    final balances = await journal.balances();
    int held(BookAccount a) => balances[(a, 'KES')] ?? 0;
    expect(held(BookAccount.money(mpesa.id)), _mpesaNow);
    expect(held(BookAccount.money(kcb.id)), _kcbNow);
    expect(held(BookAccount.fulizaOwed(mpesa.id)), 0);
    expect(held(BookAccount.notYetSorted), 0);
    // Cash taken out at the agent went into Cash in hand, made for it.
    expect(held(BookAccount.moneyInTransit), 0);
    final cash = await (db.select(
      db.accounts,
    )..where((a) => a.type.equalsValue(AccountType.cash))).getSingle();
    expect(held(BookAccount.money(cash.id)), _kes(1000));
    // The typed balance was a claim, and it never counted.
    expect(held(BookAccount.balanceCorrections), 0);

    // On hand is the sum by hand: KES 602.35 on M-Pesa, KES 13,970 at KCB
    // and KES 1,000 in hand, nothing owed.
    final read = await journal.read();
    final openings = await accounts.openings();
    expect(
      read.totalHeldAt(openings, at: monthEnd, where: (_) => true),
      _kes(602, 35) + _kes(13970) + _kes(1000),
    );

    // Every figure read from the journal (stage 4) adds up with the books
    // and with the messages.
    final from = DateTime.utc(2026, 10, 31, 21);
    final entries = await transactions.ledgerEntries(
      from: DateTime.utc(1970),
      to: DateTime.utc(9999),
    );
    final totals = LedgerTotals.of(
      entries,
      from: from,
      to: monthEnd,
      journal: read,
    );
    // Money in from John twice; KCB's moves are own transfers.
    expect(totals.incomeMinor, _kes(7000));
    expect(totals.moneyInMinor, _kes(7000));
    // Jane twice, the chemist and the grocer: the person's own KES 1,000
    // at KCB is not named yet, so it is spending too. Cash taken out at the
    // agent is the person's own money, never spending.
    expect(
      totals.spendingMinor,
      _kes(1500) + _kes(500) + _kes(350) + _kes(18000) + _kes(1000),
    );
    // Transaction costs 15 and 29, the transfer's 30, and Fuliza's 3.65.
    expect(totals.feesMinor, _kes(15) + _kes(29) + _kes(30) + _kes(3, 65));
    expect(totals.debtRepaymentMinor, _kes(365));
    expect(totals.ownTransferMinor, _kes(3000) + _kes(2030) + _kes(1000));

    final categories = {
      for (final c in await db.select(db.categories).get())
        c.id: (key: c.key, type: c.type),
    };
    final books = Books.of(
      entries,
      accounts: openings,
      categories: categories,
      journal: await journal.entries(live: true),
    );
    expect(books.unbalanced, isEmpty);
    expect(
      books.trialBalance(currency: 'KES').values.fold(0, (a, b) => a + b),
      0,
    );
    expect(
      books.balanceOf(BookAccount.money(mpesa.id), currency: 'KES'),
      _mpesaNow,
    );
    expect(
      books.balanceOf(BookAccount.money(kcb.id), currency: 'KES'),
      _kcbNow,
    );
    expect(books.balanceOf(BookAccount.balanceDifferences, currency: 'KES'), 0);
    expect(
      books.profit(currency: 'KES', from: from, to: monthEnd),
      totals.incomeMinor -
          totals.spendingMinor -
          totals.feesMinor -
          totals.taxMinor,
    );
    final byCategory = spendingByCategory(
      entries,
      from: from,
      to: monthEnd,
      journal: read,
    );
    expect(byCategory.values.fold(0, (a, b) => a + b), totals.spendingMinor);
    // What the month did to the money accounts is what came in less what
    // went out, the opening walked back from the first reported balance;
    // Cash in hand is one of them.
    final opened = books.balanceOf(
      BookAccount.openingBalances,
      currency: 'KES',
    );
    expect(
      opened + books.profit(currency: 'KES', from: from, to: monthEnd),
      _mpesaNow + _kcbNow + _kes(1000),
    );
  });
}
