import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/budget/until_next_money.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza_debt.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/ledger/on_hand.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const mpesa = 1;
const kcb = 2;
const cash = 3;
const sacco = 4;

final opened = eat(2026, 11, 1, 0);

AccountOpening account(int id, AccountType type, {int opening = 0}) =>
    AccountOpening(
      id: id,
      type: type,
      openingBalanceMinor: opening,
      openingDate: opened,
    );

LedgerEntry draw({
  required DateTime at,
  required int amount,
  required int fee,
  int? owed,
  int? id,
}) => LedgerEntry(
  id: id ?? at.millisecondsSinceEpoch ~/ 1000,
  accountId: mpesa,
  occurredAt: at,
  amountMinor: amount,
  direction: TransactionDirection.inflow,
  kind: TransactionKind.fulizaDraw,
  feeMinor: fee,
  owedAfterMinor: owed,
);

LedgerEntry correction({
  required int accountId,
  required DateTime at,
  required int difference,
  required int stated,
}) => LedgerEntry(
  id: at.millisecondsSinceEpoch ~/ 1000,
  accountId: accountId,
  occurredAt: at,
  amountMinor: difference.abs(),
  direction: difference < 0
      ? TransactionDirection.outflow
      : TransactionDirection.inflow,
  kind: TransactionKind.correction,
  source: TransactionSource.manual,
  balanceAfterMinor: stated,
);

/// The person's phone, in synthetic data: they paid 1,300 more than M-Pesa
/// held, Fuliza covered it, KCB sent M-Pesa 500 earlier, and cash is 100.
List<LedgerEntry> scenario() => [
  // KCB: a reported balance of 550, then 500 to M-Pesa leaves 50.
  entry(
    id: 10,
    accountId: kcb,
    kind: TransactionKind.bank,
    at: eat(2026, 11, 10, 9),
    amount: kes(500),
    balanceAfter: kes(50),
  ),
  inflow(id: 11, at: eat(2026, 11, 10, 9, 3), amount: kes(500)),
  // A payment that took M-Pesa to 0, then the Fuliza draw that funded it.
  entry(
    id: 12,
    kind: TransactionKind.paybill,
    at: eat(2026, 11, 12, 18, 40),
    amount: kes(1800),
    balanceAfter: 0,
  ),
  draw(
    id: 13,
    at: eat(2026, 11, 12, 18, 40).add(const Duration(seconds: 20)),
    amount: 128713,
    fee: 1287,
    owed: kes(1300),
  ),
];

void main() {
  final accounts = [
    account(mpesa, AccountType.mpesa),
    account(kcb, AccountType.bank),
    account(cash, AccountType.cash, opening: kes(100)),
    account(sacco, AccountType.sacco, opening: kes(20000)),
  ];
  final today = CalendarDate(2026, 11, 14);

  group("the person's scenario", () {
    test('M-Pesa holds 0 but is worth 1,300 below zero', () {
      final at = today.startInstant;
      final mp = accounts.first;
      expect(balanceAt(mp, scenario(), at: at), 0);
      expect(fulizaOwedAt(mp, scenario(), at: at), kes(1300));
      expect(heldAt(mp, scenario(), at: at), -kes(1300));
    });

    test('On hand is 1,150 below zero; savings and Fuliza draws are not '
        'income', () {
      final onHand = OnHand.at(
        accounts,
        scenario(),
        today: today,
        rainyDayMinor: 0,
      );
      expect(onHand.byAccount, {
        mpesa: -kes(1300),
        kcb: kes(50),
        cash: kes(100),
      });
      expect(onHand.totalMinor, -kes(1150));
      expect(onHand.fulizaOwedMinor, kes(1300));
      final totals = LedgerTotals.of(
        scenario(),
        from: opened,
        to: today.startInstant,
      );
      expect(totals.incomeMinor, 0, reason: 'the draw is borrowing');
      expect(roleOf(scenario()[3]), LedgerRole.borrowing);
    });

    test('safe to spend is 0 with a positive amount chosen earlier', () {
      final result = UntilNextMoney.calculate(
        today: today,
        basis: NextMoneyBasis.rolling,
        onHandAtStartMinor: -kes(1150),
        billsMinor: 0,
        spentTodayMinor: 0,
        paceMinor: kes(700),
        usualTodayMinor: kes(700),
        historyDays: 30,
        pinnedDailyMinor: kes(500),
        fulizaOwedMinor: kes(1300),
      );
      expect(result.onHandMinor, -kes(1150));
      expect(result.dailyMinor, 0);
      expect(result.leftTodayMinor, 0);
      expect(result.nothingSafe, isTrue);
      expect(result.belowZero, isTrue);
      expect(result.pinned, isFalse);
    });
  });

  group('wallet and Fuliza', () {
    test('a draw just after a reported balance adds nothing to the wallet', () {
      final mp = accounts.first;
      final entries = [
        entry(
          id: 1,
          kind: TransactionKind.sent,
          at: eat(2026, 11, 5, 10),
          amount: kes(200),
          balanceAfter: 0,
        ),
        draw(id: 2, at: eat(2026, 11, 5, 10, 1), amount: kes(150), fee: 150),
      ];
      expect(balanceAt(mp, entries, at: eat(2026, 11, 6)), 0);
      expect(fulizaOwedAt(mp, entries, at: eat(2026, 11, 6)), kes(150) + 150);
    });

    test('a draw with no balance near it adds its amount, not its fee', () {
      final mp = account(mpesa, AccountType.mpesa, opening: kes(10));
      final entries = [
        draw(id: 2, at: eat(2026, 11, 5, 10), amount: kes(150), fee: 150),
      ];
      expect(balanceAt(mp, entries, at: eat(2026, 11, 6)), kes(160));
    });

    test('repayments come off what is owed, never below zero', () {
      final mp = accounts.first;
      final entries = [
        draw(id: 1, at: eat(2026, 11, 5), amount: kes(100), fee: 100),
        entry(
          id: 2,
          kind: TransactionKind.fulizaRepayment,
          at: eat(2026, 11, 6),
          amount: kes(60),
        ),
      ];
      expect(fulizaOwedAt(mp, entries, at: eat(2026, 11, 7)), kes(41));
      final cleared = [
        ...entries,
        entry(
          id: 3,
          kind: TransactionKind.fulizaRepayment,
          at: eat(2026, 11, 8),
          amount: kes(50),
        ),
      ];
      expect(fulizaOwedAt(mp, cleared, at: eat(2026, 11, 9)), 0);
    });

    test('a bank account never owes Fuliza', () {
      expect(fulizaOwedAt(accounts[1], scenario(), at: today.startInstant), 0);
    });
  });

  group('FulizaDebt', () {
    test('a total that adds up leaves no daily charges', () {
      final debt = FulizaDebt.of([
        draw(id: 1, at: eat(2026, 11, 3), amount: 14000, fee: 140, owed: 14830),
        draw(
          id: 2,
          at: eat(2026, 11, 3, 15),
          amount: 2000,
          fee: 20,
          owed: 16850,
        ),
      ]);
      expect(debt.charges, isEmpty);
      expect(debt.owedMinor, 16850);
    });

    test('a total 3.00 higher three days on is 1.00 a day', () {
      final debt = FulizaDebt.of([
        draw(id: 1, at: eat(2026, 11, 3), amount: 14000, fee: 140, owed: 14830),
        draw(id: 2, at: eat(2026, 11, 6), amount: 2000, fee: 20, owed: 17150),
      ]);
      expect(debt.charges, [
        FulizaDailyCharge(CalendarDate(2026, 11, 4), 100),
        FulizaDailyCharge(CalendarDate(2026, 11, 5), 100),
        FulizaDailyCharge(CalendarDate(2026, 11, 6), 100),
      ]);
      expect(debt.owedMinor, 17150);
      expect(debt.chargesIn(YearMonth(2026, 11)), 300);
    });

    test('a remainder goes on the last day', () {
      final debt = FulizaDebt.of([
        draw(id: 1, at: eat(2026, 11, 3), amount: 10000, fee: 100, owed: 10100),
        draw(id: 2, at: eat(2026, 11, 5), amount: 1000, fee: 10, owed: 11113),
      ]);
      expect(debt.charges.map((c) => c.amountMinor), [1, 2]);
    });

    test('nothing is made up after the latest total', () {
      final mp = accounts.first;
      final entries = [
        draw(id: 1, at: eat(2026, 11, 3), amount: 14000, fee: 140, owed: 14830),
      ];
      expect(fulizaOwedAt(mp, entries, at: eat(2026, 11, 30)), 14830);
    });

    test('the first total is not daily charges: the debt may be older', () {
      final debt = FulizaDebt.of([
        draw(id: 1, at: eat(2026, 11, 3), amount: 1000, fee: 10, owed: 50000),
      ]);
      expect(debt.charges, isEmpty);
      expect(debt.owedMinor, 50000);
    });
  });

  group('corrections', () {
    test('setting M-Pesa below zero empties the wallet and owes the rest', () {
      final mp = accounts.first;
      final entries = [
        ...scenario(),
        correction(
          accountId: mpesa,
          at: eat(2026, 11, 13, 9),
          difference: -kes(200),
          stated: -kes(1500),
        ),
      ];
      final at = eat(2026, 11, 13, 10);
      expect(balanceAt(mp, entries, at: at), 0);
      expect(fulizaOwedAt(mp, entries, at: at), kes(1500));
      expect(heldAt(mp, entries, at: at), -kes(1500));
    });

    test('a correction is the new checkpoint and neither income nor '
        'spending', () {
      final bank = accounts[1];
      final fix = correction(
        accountId: kcb,
        at: eat(2026, 11, 13, 9),
        difference: kes(250),
        stated: kes(300),
      );
      final entries = [
        ...scenario(),
        fix,
        entry(
          id: 99,
          accountId: kcb,
          kind: TransactionKind.bank,
          at: eat(2026, 11, 13),
          amount: kes(20),
        ),
      ];
      expect(balanceAt(bank, entries, at: eat(2026, 11, 14)), kes(280));
      expect(roleOf(fix), LedgerRole.correction);
      final totals = LedgerTotals.of(
        [fix],
        from: opened,
        to: eat(2026, 11, 14),
      );
      expect(totals.incomeMinor, 0);
      expect(totals.spendingMinor, 0);
    });

    test("today's correction counts in On hand from the start of the day", () {
      final entries = [
        ...scenario(),
        correction(
          accountId: cash,
          at: eat(2026, 11, 14, 9),
          difference: -kes(40),
          stated: kes(60),
        ),
      ];
      final onHand = OnHand.at(
        accounts,
        entries,
        today: today,
        rainyDayMinor: 0,
      );
      expect(onHand.byAccount[cash], kes(60));
    });
  });

  group('claimed balances', () {
    test('a mistyped balance from checking a message does not inflate On '
        'hand', () {
      final entries = [
        ...scenario(),
        // Checked by hand: the reader took 38,000 for the balance.
        LedgerEntry(
          id: 50,
          accountId: kcb,
          occurredAt: eat(2026, 11, 13, 9),
          amountMinor: kes(20),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.sent,
          claimedBalanceMinor: kes(38000),
        ),
      ];
      expect(balanceAt(accounts[1], entries, at: today.startInstant), kes(30));
      final onHand = OnHand.at(
        accounts,
        entries,
        today: today,
        rainyDayMinor: 0,
      );
      expect(onHand.totalMinor, -kes(1170));
    });

    test('a claimed balance that follows becomes a checkpoint', () {
      final entries = [
        ...scenario(),
        LedgerEntry(
          id: 50,
          accountId: kcb,
          occurredAt: eat(2026, 11, 13, 9),
          amountMinor: kes(20),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.sent,
          claimedBalanceMinor: kes(30),
        ),
        // A later entry before the walk-back would differ only if it held.
        LedgerEntry(
          id: 51,
          accountId: kcb,
          occurredAt: eat(2026, 11, 13, 10),
          amountMinor: kes(5),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.sent,
          claimedBalanceMinor: kes(25),
        ),
      ];
      final walk = WalletWalk.of(accounts[1], entries);
      expect(walk.checkpoints.keys, containsAll([10, 50, 51]));
    });
  });
}
