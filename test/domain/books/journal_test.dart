import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/books/journal.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import '../../helpers/balance_oracle.dart' as oracle;
import '../fixtures.dart';

const mpesa = 1;
const kcb = 2;
const cash = 3;

const groceries = 10;
const rent = 11;
const transport = 12;
const school = 13;
const salary = 20;
const gifts = 21;

const categories = <int, BookCategory>{
  groceries: (key: null, type: CategoryType.expense),
  rent: (key: null, type: CategoryType.expense),
  transport: (key: null, type: CategoryType.expense),
  school: (key: null, type: CategoryType.expense),
  salary: (key: null, type: CategoryType.income),
  gifts: (key: null, type: CategoryType.income),
};

final accounts = [
  AccountOpening(
    id: mpesa,
    type: AccountType.mpesa,
    openingBalanceMinor: kes(1000),
    openingDate: eat(2026, 10, 31),
  ),
  AccountOpening(
    id: kcb,
    type: AccountType.bank,
    openingBalanceMinor: kes(20000),
    openingDate: eat(2026, 10, 31),
  ),
  AccountOpening(
    id: cash,
    type: AccountType.cash,
    openingBalanceMinor: kes(500),
    openingDate: eat(2026, 10, 31),
  ),
];

LedgerEntry tx(
  int id,
  DateTime at,
  int amount, {
  int account = mpesa,
  bool inflow = false,
  TransactionKind kind = TransactionKind.till,
  int fee = 0,
  int? category,
  int? payee,
  int? pair,
  int? transferAccount,
  int? balance,
  int? claimed,
  int? owedAfter,
  TransactionSource source = TransactionSource.sms,
}) => LedgerEntry(
  id: id,
  accountId: account,
  occurredAt: at,
  amountMinor: amount,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: kind,
  feeMinor: fee,
  payeeId: payee,
  categoryId: category,
  categoryType: category == null ? null : categories[category]!.type,
  transferPairId: pair,
  transferAccountId: transferAccount,
  balanceAfterMinor: balance,
  claimedBalanceMinor: claimed,
  owedAfterMinor: owedAfter,
  source: source,
);

/// A messy synthetic month on M-Pesa, a bank and cash: own transfers with a
/// fee, two Fuliza overdraws and their repayments (one worked out from the
/// balance alone, one with its own message), a Fuliza draw with no message,
/// a declined transfer, a claimed balance that agrees and one that does not,
/// a missing message, balance corrections and cash.
List<LedgerEntry> messyMonth() => [
  // Money in from someone not named yet.
  tx(
    1,
    eat(2026, 11, 1, 9),
    kes(5000),
    inflow: true,
    kind: TransactionKind.received,
    balance: kes(6000),
  ),
  tx(
    2,
    eat(2026, 11, 2, 10),
    kes(1200),
    category: groceries,
    balance: kes(4800),
  ),
  // KCB to M-Pesa, with a bank fee.
  tx(
    3,
    eat(2026, 11, 3, 10),
    kes(3000),
    account: kcb,
    kind: TransactionKind.bank,
    fee: kes(50),
    pair: 4,
  ),
  tx(
    4,
    eat(2026, 11, 3, 10, 1),
    kes(3000),
    inflow: true,
    kind: TransactionKind.received,
    pair: 3,
    balance: kes(7800),
  ),
  tx(
    5,
    eat(2026, 11, 5, 10),
    kes(7500),
    kind: TransactionKind.paybill,
    category: rent,
    balance: kes(300),
  ),
  // 1,300 with 300 in the wallet: Fuliza funds 1,000, its message after.
  tx(6, eat(2026, 11, 6), kes(1300), category: groceries, balance: 0),
  tx(
    7,
    eat(2026, 11, 6, 12, 2),
    kes(1000),
    inflow: true,
    kind: TransactionKind.fulizaDraw,
    fee: kes(10),
    owedAfter: kes(1010),
  ),
  // 500 with nothing in the wallet and no draw message: Fuliza covered it.
  tx(8, eat(2026, 11, 8), kes(500), category: transport, balance: 0),
  // Salary in; M-Pesa keeps what Fuliza is owed, with a day's charge.
  tx(
    9,
    eat(2026, 11, 10, 9),
    kes(20000),
    inflow: true,
    kind: TransactionKind.received,
    category: salary,
    payee: 1,
    balance: kes(18470),
  ),
  // Cash out to the cash account.
  tx(
    10,
    eat(2026, 11, 12, 15),
    kes(2000),
    kind: TransactionKind.withdrawal,
    fee: kes(29),
    pair: 11,
    balance: kes(16441),
  ),
  tx(
    11,
    eat(2026, 11, 12, 15),
    kes(2000),
    account: cash,
    inflow: true,
    kind: TransactionKind.deposit,
    pair: 10,
    source: TransactionSource.manual,
  ),
  tx(
    12,
    eat(2026, 11, 13, 8),
    kes(300),
    account: cash,
    category: transport,
    source: TransactionSource.manual,
  ),
  // A transfer the person unmatched: each half counts as it reads.
  tx(
    13,
    eat(2026, 11, 14, 11),
    kes(1000),
    kind: TransactionKind.sent,
    balance: kes(15441),
  ),
  tx(
    14,
    eat(2026, 11, 14, 11, 5),
    kes(1000),
    account: kcb,
    inflow: true,
    kind: TransactionKind.bank,
  ),
  // School fees past the wallet: Fuliza funds 559 plus its 6 fee.
  tx(15, eat(2026, 11, 15, 9), kes(16000), category: school, balance: 0),
  tx(
    16,
    eat(2026, 11, 15, 9, 1),
    kes(559),
    inflow: true,
    kind: TransactionKind.fulizaDraw,
    fee: kes(6),
    owedAfter: kes(565),
  ),
  // Money in, and its own repayment message with the same balance.
  tx(
    17,
    eat(2026, 11, 17, 14),
    kes(2000),
    inflow: true,
    kind: TransactionKind.received,
    category: gifts,
    payee: 2,
    balance: kes(1435),
  ),
  tx(
    18,
    eat(2026, 11, 17, 14),
    kes(565),
    kind: TransactionKind.fulizaRepayment,
    balance: kes(1435),
  ),
  // A balance typed while checking a message that agrees: a checkpoint.
  tx(
    19,
    eat(2026, 11, 20, 18),
    kes(200),
    category: groceries,
    claimed: kes(1235),
  ),
  // A missing message: the next balance is 235 short.
  tx(
    20,
    eat(2026, 11, 22, 18),
    kes(100),
    category: groceries,
    balance: kes(900),
  ),
  // The person sets KCB right.
  tx(
    21,
    eat(2026, 11, 25, 9),
    kes(50),
    account: kcb,
    inflow: true,
    kind: TransactionKind.correction,
    balance: kes(18000),
    source: TransactionSource.manual,
  ),
  // And M-Pesa to 200 below zero: an empty wallet, 200 Fuliza owed.
  tx(
    22,
    eat(2026, 11, 27, 9),
    kes(1100),
    kind: TransactionKind.correction,
    balance: kes(-200),
    source: TransactionSource.manual,
  ),
  // Money in clears it.
  tx(
    23,
    eat(2026, 11, 28, 9),
    kes(1000),
    inflow: true,
    kind: TransactionKind.received,
    category: gifts,
    payee: 2,
    balance: kes(800),
  ),
  // A mistyped claimed balance: not a checkpoint.
  tx(
    24,
    eat(2026, 11, 29, 9),
    kes(100),
    category: groceries,
    claimed: kes(9999),
  ),
  // KCB to M-Pesa, named by the person, its other side not here yet.
  tx(
    25,
    eat(2026, 11, 30, 9),
    kes(500),
    account: kcb,
    kind: TransactionKind.bank,
    transferAccount: mpesa,
  ),
];

int sumIn(JournalEntry e, String currency) =>
    e.currency == currency ? e.lines.fold(0, (s, l) => s + l.amountMinor) : 0;

void main() {
  final history = messyMonth();
  final journal = postJournal(
    accounts: accounts,
    history: history,
    categories: categories,
  );
  final monthEnd = eat(2026, 12, 1, 0);

  test('every entry sums to zero per currency', () {
    for (final e in journal) {
      expect(sumIn(e, e.currency), 0, reason: '$e');
    }
  });

  test('every transaction has exactly one entry', () {
    final ids = [
      for (final e in journal)
        if (e.source == JournalSource.transaction) e.sourceId,
    ];
    expect(ids..sort(), [for (final e in history) e.id]..sort());
  });

  test('each account in the journal equals the balance code at month end '
      'and at the end of every day', () {
    final days = [
      for (var d = 1; d <= 30; d++) eat(2026, 11, d, 23, 59),
      monthEnd,
    ];
    final off = <String>[];
    for (final at in days) {
      for (final a in accounts) {
        final journalMoney = journalBalance(
          journal,
          BookAccount.money(a.id),
          currency: 'KES',
          at: at,
        );
        final records = oracle.balanceAt(a, history, at: at);
        if (journalMoney != records) {
          off.add('${a.id} at $at: journal $journalMoney, records $records');
        }
        if (a.canOweFuliza) {
          final owed = journalBalance(
            journal,
            BookAccount.fulizaOwed(a.id),
            currency: 'KES',
            at: at,
          );
          final records = oracle.fulizaOwedAt(a, history, at: at);
          if (owed != records) {
            off.add('Fuliza ${a.id} at $at: journal $owed, records $records');
          }
        }
      }
    }
    expect(off, isEmpty);
  });

  test('the month ends where the balance code says, in figures', () {
    int money(int id) => journalBalance(
      journal,
      BookAccount.money(id),
      currency: 'KES',
      at: monthEnd,
    );
    expect(money(mpesa), kes(700));
    expect(money(kcb), kes(17500));
    expect(money(cash), kes(2200));
    expect(
      journalBalance(
        journal,
        const BookAccount.fulizaOwed(mpesa),
        currency: 'KES',
        at: monthEnd,
      ),
      0,
    );
  });

  test('Fuliza draws are owed, repayments clear them, the rest is fees', () {
    JournalEntry of(int id) => journal.singleWhere(
      (e) => e.source == JournalSource.transaction && e.sourceId == id,
    );
    int line(JournalEntry e, BookAccount a) => e.lines
        .where((l) => l.account == a)
        .fold(0, (s, l) => s + l.amountMinor);
    const owed = BookAccount.fulizaOwed(mpesa);
    const money = BookAccount.money(mpesa);

    // The payment funded by the draw after it: 300 from the wallet, 1,000
    // through Money in transit.
    expect(line(of(6), money), -kes(300));
    expect(line(of(6), BookAccount.moneyInTransit), -kes(1000));
    // The draw: 1,010 owed, 1,000 to transit, 10 fee.
    expect(line(of(7), owed), -kes(1010));
    expect(line(of(7), BookAccount.moneyInTransit), kes(1000));
    expect(line(of(7), BookAccount.fulizaCharges), kes(10));
    // No draw message: the 500 payment was covered, plus a 5 access fee.
    expect(line(of(8), owed), -kes(505));
    expect(line(of(8), BookAccount.fulizaCharges), kes(5));
    // Salary: 1,515 owed came off it, with 15 of daily charges.
    expect(line(of(9), money), kes(18470));
    expect(line(of(9), owed), kes(1515));
    expect(line(of(9), BookAccount.fulizaCharges), kes(15));
    // Money in with its own repayment message: the repayment posts with the
    // money in, as the balance shows it; the message adds nothing more.
    expect(line(of(17), owed), kes(565));
    expect(of(18).lines, isEmpty);
    // Money in after the correction clears the 200 it said was owed.
    expect(line(of(23), owed), kes(200));
  });

  test('own transfers meet in Money in transit; a named one waits there', () {
    expect(
      journalBalance(
        journal,
        BookAccount.moneyInTransit,
        currency: 'KES',
        at: monthEnd,
      ),
      kes(500),
    );
  });

  test('a declined transfer counts as spending and income', () {
    final sent = journal.singleWhere(
      (e) => e.source == JournalSource.transaction && e.sourceId == 13,
    );
    expect(
      sent.lines.map((l) => l.account),
      containsAll([
        const BookAccount.money(mpesa),
        BookAccount.uncategorisedSpending,
      ]),
    );
    final received = journal.singleWhere(
      (e) => e.source == JournalSource.transaction && e.sourceId == 14,
    );
    expect(
      received.lines.map((l) => l.account),
      contains(BookAccount.uncategorisedIncome),
    );
  });

  test('corrections post to Balance corrections, gaps to Not yet sorted', () {
    final corrections = journalBalance(
      journal,
      BookAccount.balanceCorrections,
      currency: 'KES',
      at: monthEnd,
    );
    // KCB set 50 up; M-Pesa set from 900 to 200 below zero.
    expect(corrections, kes(50) - kes(1100));
    final gaps = [
      for (final e in journal)
        if (e.source == JournalSource.balanceDifference) e,
    ];
    expect(gaps, hasLength(1));
    expect(gaps.single.sourceId, 20);
    expect(gaps.single.lines.first.amountMinor, -kes(235));
    // Money in from someone not named (5,000), less the missing 235.
    expect(
      journalBalance(
        journal,
        BookAccount.notYetSorted,
        currency: 'KES',
        at: monthEnd,
      ),
      kes(5000) - kes(235),
    );
  });

  test('the journal is the same whatever order the records come in', () {
    final again = postJournal(
      accounts: accounts.reversed,
      history: history.reversed,
      categories: categories,
    );
    String shape(Iterable<JournalEntry> es) => ([
      for (final e in es)
        '${e.source.name} ${e.sourceId} ${[for (final l in e.lines) '${l.account.key}=${l.amountMinor}']..sort()}',
    ]..sort()).join('\n');
    expect(shape(again), shape(journal));
  });

  test('account keys round-trip', () {
    for (final a in [
      const BookAccount.money(3),
      const BookAccount.fulizaOwed(1),
      const BookAccount.category(7, income: true),
      BookAccount.notYetSorted,
      BookAccount.moneyInTransit,
      BookAccount.balanceCorrections,
      BookAccount.openingBalances,
    ]) {
      expect(BookAccount.parse(a.key), a);
    }
    expect(BookAccount.parse('nonsense'), isNull);
    expect(BookAccount.parse('money'), isNull);
    expect(BookAccount.parse('notYetSorted:4'), isNull);
  });
}
