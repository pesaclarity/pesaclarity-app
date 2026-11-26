// Stage 4 of decision 0018 on random histories, in the style of decision
// 0027's: Plan, Insights, Activity, reports, tax and the business books
// all read one journal, so on any history they must agree with each other,
// with the balances, and with the balances the messages reported. Each run
// is a month of two spaces sharing the owner's M-Pesa (decision 0027):
// Personal with its M-Pesa (Fuliza and all), a KCB account and money held
// for a stall, and the stall with cash and the owner's account. Messages go
// missing, payments are switched between the spaces, Fuliza covers what
// the wallet cannot, and KCB sends money to M-Pesa for a fee.
//
// Made-up numbers only.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/books/journal.dart';
import 'package:pesaclarity/src/domain/books/journal_balances.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/tags/tag_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../../helpers/balance_oracle.dart';
import '../fixtures.dart';

final _start = eat(2026, 11, 1, 0);
final _end = eat(2026, 12, 1, 0);

AccountOpening _account(int id, AccountType type, int balance) =>
    AccountOpening(
      id: id,
      type: type,
      openingBalanceMinor: balance,
      openingDate: _start,
    );

// Personal: M-Pesa 1, Held for the stall on it 2, KCB 4. Food 1 and
// Family 3 are spending, Salary 2 income, KRA 5 tax, Chama 6 savings.
final _personalAccounts = [
  _account(1, AccountType.mpesa, kes(8000)),
  _account(2, AccountType.heldForSpace, 0),
  _account(4, AccountType.bank, kes(40000)),
];
const _personalCategories = <int, BookCategory>{
  1: (key: 'food', type: CategoryType.expense),
  2: (key: 'salary', type: CategoryType.income),
  3: (key: 'family', type: CategoryType.expense),
  5: (key: 'kra', type: CategoryType.tax),
  6: (key: 'chama', type: CategoryType.savings),
};

// The stall: cash 1, the owner's account on Personal's M-Pesa 3. Sales
// 10, Stock 11.
final _stallAccounts = [
  _account(1, AccountType.cash, kes(2000)),
  _account(3, AccountType.ownersAccount, 0),
];
const _stallCategories = <int, BookCategory>{
  10: (key: 'sales', type: CategoryType.income),
  11: (key: 'stock', type: CategoryType.expense),
};

LedgerEntry _tx(
  int id,
  int account,
  DateTime at,
  int amount, {
  required Map<int, BookCategory> categories,
  bool inflow = false,
  int? category,
  int fee = 0,
  int? balance,
  TransactionKind? kind,
  int? pair,
  String? linked,
}) => LedgerEntry(
  id: id,
  accountId: account,
  occurredAt: at,
  amountMinor: amount,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: kind ?? (inflow ? TransactionKind.received : TransactionKind.paybill),
  feeMinor: fee,
  categoryId: category,
  categoryType: categories[category]?.type,
  payeeId: category == null ? null : 1,
  balanceAfterMinor: balance,
  transferPairId: pair,
  linkedSpaceId: linked,
);

/// What a payment switched to the stall leaves on Personal's M-Pesa.
LedgerEntry _record(
  int id,
  DateTime at,
  int amount,
  int balance,
  bool inflow,
) => LedgerEntry(
  id: -id,
  accountId: 1,
  occurredAt: at,
  amountMinor: amount,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: inflow ? TransactionKind.received : TransactionKind.paybill,
  balanceAfterMinor: balance,
  linkedSpaceId: 'stall',
  heldForAccountId: 2,
);

/// Checks one space: every view over its journal agrees with the books,
/// the balances and the reported balances.
void _expectViewsAgree(
  String what,
  List<AccountOpening> accounts,
  Map<int, BookCategory> categories,
  List<LedgerEntry> history,
) {
  final journal = postJournal(
    accounts: accounts,
    history: history,
    categories: categories,
  );
  final balances = JournalBalances(journal);
  final books = Books.of(history, accounts: accounts, categories: categories);
  // What lists, totals and reports read: transactions only.
  final transactions = [
    for (final e in history)
      if (!e.isBalanceRecord) e,
  ];

  // The books are the journal: they balance, carry no plug, and every
  // money account is what the balances show and the oracle works out.
  for (final e in books.entries) {
    expect(e.isBalanced, isTrue, reason: '$what: $e');
  }
  expect(
    books.trialBalance(currency: 'KES').values.fold(0, (a, b) => a + b),
    0,
    reason: what,
  );
  expect(
    books.balanceOf(BookAccount.balanceDifferences, currency: 'KES'),
    0,
    reason: '$what: no balance difference plug',
  );
  for (final a in accounts) {
    final account = BookAccount.forAccount(a.id, a.type);
    expect(
      books.balanceOf(account, currency: 'KES'),
      balances.balanceOf(account, currency: 'KES'),
      reason: '$what: account ${a.id} in the books and the balances',
    );
    if (a.type.isBetweenSpaces) continue;
    expect(
      balances.walletAt(a, at: _end),
      balanceWithFundedDrawsAt(a, history, at: _end),
      reason: '$what: account ${a.id} against the records',
    );
  }

  // Insights, Activity, Plan, reports and tax: every figure read from the
  // journal adds up with the books.
  final totals = LedgerTotals.of(
    transactions,
    from: _start,
    to: _end,
    journal: balances,
  );
  int flow(bool Function(BookAccount a) where) {
    var sum = 0;
    for (final e in books.entries) {
      for (final l in e.lines) {
        if (where(l.account)) sum += l.amountMinor;
      }
    }
    return sum;
  }

  expect(
    totals.incomeMinor,
    -flow((a) => a.accountClass == BookAccountClass.income),
    reason: '$what: income',
  );
  expect(
    totals.spendingMinor,
    flow(
      (a) =>
          a.kind == BookAccountKind.spendingCategory ||
          a.kind == BookAccountKind.uncategorisedSpending,
    ),
    reason: '$what: spending',
  );
  expect(
    totals.feesMinor,
    flow(
      (a) =>
          a == BookAccount.fees ||
          a == BookAccount.fulizaCharges ||
          a == BookAccount.exchangeCost,
    ),
    reason: '$what: fees and charges, each once',
  );
  expect(totals.taxMinor, flow((a) => a == BookAccount.tax), reason: what);
  expect(
    books.profit(currency: 'KES', from: _start, to: _end),
    totals.incomeMinor -
        totals.spendingMinor -
        totals.feesMinor -
        totals.taxMinor,
    reason: '$what: profit in the books and in Insights',
  );
  final byCategory = spendingByCategory(
    transactions,
    from: _start,
    to: _end,
    journal: balances,
  );
  expect(
    byCategory.values.fold(0, (a, b) => a + b),
    totals.spendingMinor,
    reason: '$what: the categories add up',
  );
  final chart = SpendingChart.of(
    transactions,
    period: ChartPeriod.month,
    today: CalendarDate(2026, 11, 30),
    journal: balances,
  );
  // The chart shows what was spent in each category and on fees, where
  // more was spent than came back.
  int shown(int minor) => minor > 0 ? minor : 0;
  expect(
    chart.slices.fold(0, (s, slice) => s + slice.amountMinor),
    byCategory.values.fold(0, (s, v) => s + shown(v)) + shown(totals.feesMinor),
    reason: '$what: the spending chart',
  );
  final week = weekInOut(
    transactions,
    today: CalendarDate(2026, 11, 30),
    journal: balances,
  );
  final weekTotals = LedgerTotals.of(
    transactions,
    from: startOfWeek(CalendarDate(2026, 11, 30)).startInstant,
    to: _end,
    journal: balances,
  );
  expect(
    week.outMinor,
    weekTotals.spendingMinor + weekTotals.feesMinor,
    reason: what,
  );
  final review = MonthReview.of(
    MonthPlan(
      month: YearMonth(2026, 11),
      lines: const [],
      categories: const {},
    ),
    transactions,
    journal: balances,
  );
  expect(
    review.actualMinor,
    totals.spendingMinor + totals.taxMinor + totals.savingMinor,
    reason: '$what: Plan counts what each category paid',
  );

  // What only the journal changes: the rest is the same as read from the
  // transactions alone.
  final plain = LedgerTotals.of(transactions, from: _start, to: _end);
  expect(totals.incomeMinor, plain.incomeMinor, reason: what);
  expect(totals.spendingMinor, plain.spendingMinor, reason: what);
  expect(totals.taxMinor, plain.taxMinor, reason: what);
  expect(totals.savingMinor, plain.savingMinor, reason: what);
  expect(totals.moneyInMinor, plain.moneyInMinor, reason: what);
  expect(totals.ownTransferMinor, plain.ownTransferMinor, reason: what);
  expect(totals.debtRepaymentMinor, plain.debtRepaymentMinor, reason: what);
}

void main() {
  test('random histories: every view over the journal agrees with the '
      'books, the balances and the reported balances, in both spaces', () {
    final random = Random(18);
    // How many runs had Fuliza, a transfer fee and a missing message.
    var withFuliza = 0;
    var withFees = 0;
    var withGaps = 0;
    for (var run = 0; run < 40; run++) {
      final personal = <LedgerEntry>[];
      final stall = <LedgerEntry>[];
      var wallet = kes(8000);
      var kcb = kes(40000);
      var owed = 0;
      // What the journal changes against the transactions alone: what
      // transfers lost on the way, and Fuliza's fee, which the
      // transactions count on the draw and again on its repayment.
      var lost = 0;
      var twice = 0;
      // Money out of M-Pesa whose message never came, and whether M-Pesa
      // has reported a balance since.
      var missing = 0;
      var unseen = false;
      var at = eat(2026, 11, 1, 8);
      var id = 0;
      for (var step = 0; step < 30; step++) {
        at = at.add(Duration(minutes: 30 + random.nextInt(900)));
        final amount = kes(50 + random.nextInt(3000));
        id++;
        switch (random.nextInt(9)) {
          case 0:
            // A sale switched to the stall. (M-Pesa would take Fuliza
            // out of it first: those wait until Fuliza is repaid.)
            if (owed > 0) continue;
            wallet += amount;
            personal.add(_record(id, at, amount, wallet, true));
            stall.add(
              _tx(
                id,
                3,
                at,
                amount,
                categories: _stallCategories,
                inflow: true,
                category: 10,
                linked: 'personal',
              ),
            );
          case 1:
            // A stall cost paid from the owner's M-Pesa.
            if (amount > wallet) continue;
            wallet -= amount;
            personal.add(_record(id, at, amount, wallet, false));
            stall.add(
              _tx(
                id,
                3,
                at,
                amount,
                categories: _stallCategories,
                category: 11,
                linked: 'personal',
              ),
            );
          case 2:
            // Salary into M-Pesa; it repays any Fuliza first.
            wallet += amount;
            final repaid = owed;
            wallet -= repaid;
            personal.add(
              _tx(
                id,
                1,
                at,
                amount,
                categories: _personalCategories,
                inflow: true,
                category: 2,
                balance: wallet,
              ),
            );
            if (repaid > 0) {
              id++;
              personal.add(
                _tx(
                  id,
                  1,
                  at.add(const Duration(seconds: 20)),
                  repaid,
                  categories: _personalCategories,
                  kind: TransactionKind.fulizaRepayment,
                  balance: wallet,
                ),
              );
              owed = 0;
            }
          case 3:
            // Spending on M-Pesa with a transaction cost; with too little
            // in it, Fuliza covers the rest.
            final fee = kes(random.nextInt(3) * 15);
            final category = random.nextBool() ? 1 : 3;
            if (amount + fee <= wallet) {
              wallet -= amount + fee;
              personal.add(
                _tx(
                  id,
                  1,
                  at,
                  amount,
                  categories: _personalCategories,
                  category: category,
                  fee: fee,
                  balance: wallet,
                  kind: TransactionKind.till,
                ),
              );
            } else if (owed == 0 && !unseen && amount > wallet) {
              // Fuliza only on a wallet whose balance is known: with a
              // message missing, what Fuliza covered is not.
              final covered = amount - wallet;
              final access = (covered + 50) ~/ 100;
              wallet = 0;
              owed = covered + access;
              twice += access;
              personal.add(
                _tx(
                  id,
                  1,
                  at,
                  amount,
                  categories: _personalCategories,
                  category: category,
                  balance: 0,
                  kind: TransactionKind.till,
                ),
              );
              id++;
              personal.add(
                LedgerEntry(
                  id: id,
                  accountId: 1,
                  occurredAt: at.add(const Duration(seconds: 35)),
                  amountMinor: covered,
                  direction: TransactionDirection.inflow,
                  kind: TransactionKind.fulizaDraw,
                  feeMinor: access,
                  owedAfterMinor: owed,
                ),
              );
            }
          case 4:
            // KCB into M-Pesa; sometimes KCB takes a fee on the way.
            final fee = random.nextBool() ? kes(30) : 0;
            if (amount + fee > kcb) continue;
            kcb -= amount + fee;
            wallet += amount;
            final repaid = owed;
            wallet -= repaid;
            lost += fee;
            personal
              ..add(
                _tx(
                  id,
                  4,
                  at,
                  amount + fee,
                  categories: _personalCategories,
                  balance: kcb,
                  kind: TransactionKind.bank,
                  pair: id + 1,
                ),
              )
              ..add(
                _tx(
                  id + 1,
                  1,
                  at.add(const Duration(minutes: 1)),
                  amount,
                  categories: _personalCategories,
                  inflow: true,
                  balance: wallet,
                  kind: TransactionKind.received,
                  pair: id,
                ),
              );
            id++;
            if (repaid > 0) {
              id++;
              personal.add(
                _tx(
                  id,
                  1,
                  at.add(const Duration(minutes: 1, seconds: 20)),
                  repaid,
                  categories: _personalCategories,
                  kind: TransactionKind.fulizaRepayment,
                  balance: wallet,
                ),
              );
              owed = 0;
            }
          case 5:
            // Tax or savings from KCB.
            if (amount > kcb) continue;
            kcb -= amount;
            personal.add(
              _tx(
                id,
                4,
                at,
                amount,
                categories: _personalCategories,
                category: random.nextBool() ? 5 : 6,
                balance: kcb,
                kind: TransactionKind.bank,
              ),
            );
          case 6:
            // A payment whose message never came: the next balance M-Pesa
            // reports is short, and the gap waits in Not yet sorted.
            if (amount > wallet) continue;
            wallet -= amount;
            // Before M-Pesa's first reported balance, the opening is walked
            // back from it, so nothing is missing yet.
            if (personal.any(
              (e) => e.accountId == 1 && e.balanceAfterMinor != null,
            )) {
              missing += amount;
            }
            unseen = true;
          case 7:
            // The stall's own cash: a sale, or stock.
            final sale = random.nextBool();
            stall.add(
              _tx(
                id,
                1,
                at,
                amount,
                categories: _stallCategories,
                inflow: sale,
                category: sale ? 10 : 11,
                kind: TransactionKind.bank,
              ),
            );
          default:
            // A refund of earlier food, into M-Pesa.
            wallet += amount;
            final repaid = owed;
            wallet -= repaid;
            personal.add(
              _tx(
                id,
                1,
                at,
                amount,
                categories: _personalCategories,
                inflow: true,
                category: 1,
                balance: wallet,
                kind: TransactionKind.reversal,
              ),
            );
            if (repaid > 0) {
              id++;
              personal.add(
                _tx(
                  id,
                  1,
                  at.add(const Duration(seconds: 20)),
                  repaid,
                  categories: _personalCategories,
                  kind: TransactionKind.fulizaRepayment,
                  balance: wallet,
                ),
              );
              owed = 0;
            }
        }
        if (personal.lastOrNull case final last?
            when last.accountId == 1 && last.balanceAfterMinor != null) {
          unseen = false;
        }
      }
      // M-Pesa reports its balance once more, so a message missed last
      // shows.
      id++;
      personal.add(
        _tx(
          id,
          1,
          eat(2026, 11, 30, 20),
          kes(1),
          categories: _personalCategories,
          inflow: true,
          category: 2,
          balance: wallet + kes(1) - owed,
        ),
      );
      wallet += kes(1) - owed;
      if (owed > 0) {
        id++;
        personal.add(
          _tx(
            id,
            1,
            eat(2026, 11, 30, 20, 1),
            owed,
            categories: _personalCategories,
            kind: TransactionKind.fulizaRepayment,
            balance: wallet,
          ),
        );
        owed = 0;
      }

      if (twice > 0) withFuliza++;
      if (lost > 0) withFees++;
      if (missing > 0) withGaps++;
      final what = 'run $run';
      _expectViewsAgree(
        '$what, Personal',
        _personalAccounts,
        _personalCategories,
        personal,
      );
      _expectViewsAgree(
        '$what, the stall',
        _stallAccounts,
        _stallCategories,
        stall,
      );

      final p = JournalBalances(
        postJournal(
          accounts: _personalAccounts,
          history: personal,
          categories: _personalCategories,
        ),
      );
      final s = JournalBalances(
        postJournal(
          accounts: _stallAccounts,
          history: stall,
          categories: _stallCategories,
        ),
      );
      // Every balance is what the messages reported.
      expect(p.walletAt(_personalAccounts[0], at: _end), wallet, reason: what);
      expect(p.walletAt(_personalAccounts[2], at: _end), kcb, reason: what);
      expect(p.fulizaOwedAt(_personalAccounts[0], at: _end), 0, reason: what);
      // Money between spaces: Held for the stall is the stall's money on
      // the owner's account.
      expect(
        p.balanceOf(const BookAccount.heldForSpace(2), currency: 'KES'),
        s.balanceOf(const BookAccount.ownersAccount(3), currency: 'KES'),
        reason: what,
      );
      // What no record explains waits in Not yet sorted, never as income
      // or spending.
      expect(
        p.balanceOf(BookAccount.notYetSorted, currency: 'KES'),
        -missing,
        reason: what,
      );
      expect(p.balanceOf(BookAccount.moneyInTransit, currency: 'KES'), 0);

      // Fees: the journal counts what a transfer lost on the way, and
      // Fuliza's fee once, as the transactions alone now count it too.
      final transactions = [
        for (final e in personal)
          if (!e.isBalanceRecord) e,
      ];
      final plain = LedgerTotals.of(transactions, from: _start, to: _end);
      final posted = LedgerTotals.of(
        transactions,
        from: _start,
        to: _end,
        journal: p,
      );
      expect(
        posted.feesMinor,
        plain.feesMinor + lost,
        reason: '$what: ${FulizaLedger.of(transactions)}',
      );
    }
    expect(withFuliza, greaterThan(5));
    expect(withFees, greaterThan(5));
    expect(withGaps, greaterThan(5));
  });
}
