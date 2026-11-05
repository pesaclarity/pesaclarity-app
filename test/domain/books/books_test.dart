import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_summary.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const categories = <int, BookCategory>{
  1: (key: 'sales', type: CategoryType.income),
  2: (key: 'stock', type: CategoryType.expense),
  3: (key: 'wages', type: CategoryType.expense),
  4: (key: 'owner_pay', type: CategoryType.transfer),
  5: (key: 'kra', type: CategoryType.tax),
  6: (key: 'chama', type: CategoryType.savings),
  7: (key: 'loan', type: CategoryType.debt),
};

AccountOpening opening(int id, {int balance = 0, DateTime? at}) =>
    AccountOpening(
      id: id,
      type: id == 2 ? AccountType.cash : AccountType.mpesa,
      openingBalanceMinor: balance,
      openingDate: at ?? eat(2026, 10, 1, 0),
    );

/// A month of a small business on M-Pesa (account 1) and cash (account 2).
List<LedgerEntry> month() => [
  inflow(
    at: eat(2026, 11, 2),
    amount: kes(15000),
    payeeId: 1,
    categoryId: 1,
    categoryType: CategoryType.income,
  ),
  entry(
    at: eat(2026, 11, 3),
    amount: kes(11000),
    categoryId: 2,
    categoryType: CategoryType.expense,
    fee: kes(30),
  ),
  // Uncategorised money in and out.
  inflow(
    at: eat(2026, 11, 4),
    amount: kes(800),
    kind: TransactionKind.till,
    payeeId: 9,
  ),
  entry(at: eat(2026, 11, 4, 13), amount: kes(250)),
  // Own transfer: withdraw 2,000 from M-Pesa into the cash drawer.
  entry(
    id: 501,
    at: eat(2026, 11, 5),
    amount: kes(2000),
    kind: TransactionKind.withdrawal,
    transferPairId: 502,
    fee: kes(29),
  ),
  inflow(
    id: 502,
    at: eat(2026, 11, 5),
    amount: kes(2000),
    accountId: 2,
    kind: TransactionKind.bank,
  ).copyWith(transferPairId: 501),
  // Paying the owner, wages, tax, savings.
  entry(
    at: eat(2026, 11, 6),
    amount: kes(6000),
    categoryId: 4,
    categoryType: CategoryType.transfer,
  ),
  entry(
    at: eat(2026, 11, 7),
    amount: kes(3000),
    accountId: 2,
    kind: TransactionKind.bank,
    categoryId: 3,
    categoryType: CategoryType.expense,
  ),
  entry(
    at: eat(2026, 11, 8),
    amount: kes(450),
    kind: TransactionKind.paybill,
    categoryId: 5,
    categoryType: CategoryType.tax,
  ),
  entry(
    at: eat(2026, 11, 9),
    amount: kes(1000),
    kind: TransactionKind.sent,
    categoryId: 6,
    categoryType: CategoryType.savings,
  ),
  // Fuliza: draw, then repay with its fee share.
  inflow(
    at: eat(2026, 11, 10),
    amount: kes(500),
    kind: TransactionKind.fulizaDraw,
  ),
  entry(
    at: eat(2026, 11, 12),
    amount: kes(505),
    kind: TransactionKind.fulizaRepayment,
  ),
  // A charge, a refund in and money sent back out.
  entry(at: eat(2026, 11, 13), amount: kes(15), kind: TransactionKind.charge),
  inflow(
    at: eat(2026, 11, 14),
    amount: kes(300),
    kind: TransactionKind.reversal,
    categoryId: 2,
    categoryType: CategoryType.expense,
  ),
  entry(
    at: eat(2026, 11, 14, 15),
    amount: kes(200),
    kind: TransactionKind.reversal,
    categoryId: 1,
    categoryType: CategoryType.income,
  ),
  // Someone not named yet, and borrowing from family.
  inflow(at: eat(2026, 11, 15), amount: kes(700)),
  inflow(
    at: eat(2026, 11, 16),
    amount: kes(4000),
    payeeId: 3,
    categoryId: 7,
    categoryType: CategoryType.debt,
  ),
];

void expectBalanced(Books books) {
  expect(books.unbalanced, isEmpty);
  final trial = books.trialBalance(currency: 'KES');
  expect(trial.values.fold(0, (a, b) => a + b), 0);
}

void main() {
  final from = eat(2026, 11, 1, 0);
  final to = eat(2026, 12, 1, 0);
  final accounts = [opening(1, balance: kes(5000)), opening(2)];

  test('every entry balances and the trial balance is zero', () {
    final books = Books.of(month(), accounts: accounts, categories: categories);
    expectBalanced(books);
    expect(
      books.entries.where((e) => e.source == JournalSource.opening),
      hasLength(2),
    );
  });

  test('profit agrees with the totals the app shows', () {
    final history = month();
    final books = Books.of(history, accounts: accounts, categories: categories);
    final totals = LedgerTotals.of(history, from: from, to: to);
    final expected =
        totals.incomeMinor -
        totals.spendingMinor -
        totals.feesMinor -
        totals.taxMinor;
    expect(books.profit(currency: 'KES', from: from, to: to), expected);

    final summary = SpaceSummary.of(
      SpaceKind.business,
      history,
      today: CalendarDate(2026, 11, 30),
      categories: {
        for (final MapEntry(:key, :value) in categories.entries)
          key: (key: value.key, name: value.key ?? '', type: value.type),
      },
      balanceMinor: 0,
    );
    expect(
      books.profit(currency: 'KES', from: from, to: to),
      summary.profitMinor,
    );
  });

  test('money accounts agree with the balances the app shows', () {
    final history = month();
    final books = Books.of(history, accounts: accounts, categories: categories);
    for (final at in [eat(2026, 11, 3, 18), eat(2026, 11, 10, 18), to]) {
      for (final a in accounts) {
        expect(
          books.balanceOf(BookAccount.money(a.id), currency: 'KES', to: at),
          balanceAt(a, history, at: at),
          reason: 'account ${a.id} at $at',
        );
      }
    }
  });

  test('where each kind of money goes', () {
    final books = Books.of(month(), accounts: accounts, categories: categories);
    int bal(BookAccount a) => books.balanceOf(a, currency: 'KES');
    expect(bal(BookAccount.ownerPay), -kes(6000)); // equity reduced
    expect(bal(BookAccount.ownTransfers), 0); // both halves met
    expect(
      bal(BookAccount.borrowed),
      kes(4000),
    ); // Fuliza repaid, family loan owed
    expect(bal(BookAccount.awaitingPayee), kes(700));
    expect(bal(BookAccount.savings), kes(1000));
    expect(bal(BookAccount.tax), kes(450));
    expect(bal(BookAccount.uncategorisedIncome), kes(800));
    expect(bal(BookAccount.uncategorisedSpending), kes(250));
    expect(bal(const BookAccount.category(2, income: false)), kes(11000 - 300));
    expect(bal(const BookAccount.category(1, income: true)), kes(15000 - 200));
    // 30 + 29 transaction costs, 15 charge, 5 Fuliza fee.
    expect(bal(BookAccount.fees), kes(79));
    expect(bal(BookAccount.openingBalances), kes(5000));
  });

  test('a reported balance the records miss becomes a balance difference', () {
    final history = [
      inflow(
        at: eat(2026, 11, 2),
        amount: kes(1000),
        payeeId: 1,
        categoryId: 1,
        categoryType: CategoryType.income,
      ),
      // M-Pesa says 7,500 after this: 1,500 more than the records explain.
      entry(
        at: eat(2026, 11, 3),
        amount: kes(500),
        categoryId: 2,
        categoryType: CategoryType.expense,
        balanceAfter: kes(7500),
      ),
      entry(
        at: eat(2026, 11, 4),
        amount: kes(200),
        categoryId: 2,
        categoryType: CategoryType.expense,
      ),
    ];
    final a = opening(1, balance: kes(5000));
    final books = Books.of(history, accounts: [a], categories: categories);
    expectBalanced(books);
    expect(
      books.balanceOf(const BookAccount.money(1), currency: 'KES'),
      kes(7300),
    );
    expect(balanceAt(a, history, at: to), kes(7300));
    expect(
      books.balanceOf(BookAccount.balanceDifferences, currency: 'KES'),
      kes(2000),
    );
    // The opening is walked back from the first reported balance.
    expect(
      books.balanceOf(
        const BookAccount.money(1),
        currency: 'KES',
        to: eat(2026, 11, 2, 18),
      ),
      balanceAt(a, history, at: eat(2026, 11, 2, 18)),
    );
  });

  test('entries before an account opens do not move its balance', () {
    final history = [
      entry(
        at: eat(2026, 9, 20),
        amount: kes(400),
        categoryId: 2,
        categoryType: CategoryType.expense,
      ),
      inflow(
        at: eat(2026, 11, 2),
        amount: kes(1000),
        payeeId: 1,
        categoryId: 1,
        categoryType: CategoryType.income,
      ),
    ];
    final a = opening(1, balance: kes(5000));
    final books = Books.of(history, accounts: [a], categories: categories);
    expectBalanced(books);
    expect(
      books.balanceOf(const BookAccount.money(1), currency: 'KES'),
      balanceAt(a, history, at: to),
    );
  });

  test('random histories always balance and match the app balances', () {
    final random = Random(7);
    for (var round = 0; round < 200; round++) {
      final history = <LedgerEntry>[];
      final n = random.nextInt(40);
      for (var i = 0; i < n; i++) {
        final kind = TransactionKind
            .values[random.nextInt(TransactionKind.values.length)];
        final cat = random.nextInt(9); // 0 and 8 have no category
        final known = categories[cat];
        final at = eat(
          2026,
          10,
          1 + random.nextInt(60) ~/ 2,
          random.nextInt(20) + 1,
        );
        final out = random.nextBool();
        final e = LedgerEntry(
          id: 10000 + round * 100 + i,
          accountId: 1 + random.nextInt(2),
          occurredAt: at,
          amountMinor: random.nextInt(100000),
          direction: out
              ? TransactionDirection.outflow
              : TransactionDirection.inflow,
          kind: kind,
          currency: 'KES',
          feeMinor: random.nextInt(4) == 0 ? random.nextInt(5000) : 0,
          payeeId: random.nextBool() ? random.nextInt(5) : null,
          categoryId: cat == 0 || cat == 8 ? null : cat,
          categoryType: known?.type,
          balanceAfterMinor: random.nextInt(6) == 0
              ? random.nextInt(500000)
              : null,
        );
        history.add(e);
      }
      final accts = [
        opening(1, balance: random.nextInt(100000), at: eat(2026, 10, 3, 0)),
        opening(2, balance: random.nextInt(100000)),
      ];
      final books = Books.of(history, accounts: accts, categories: categories);
      expectBalanced(books);
      for (final a in accts) {
        for (final at in [
          eat(2026, 10, 10),
          eat(2026, 10, 25),
          eat(2026, 12, 31),
        ]) {
          expect(
            books.balanceOf(BookAccount.money(a.id), currency: 'KES', to: at),
            balanceAt(a, history, at: at),
            reason: 'round $round, account ${a.id}, at $at',
          );
        }
      }
    }
  });
}
