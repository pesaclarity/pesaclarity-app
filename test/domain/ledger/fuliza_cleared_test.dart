import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balance_check.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza_debt.dart';
import 'package:pesaclarity/src/domain/ledger/gap_leads.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const mpesa = 1;

final mp = AccountOpening(
  id: mpesa,
  type: AccountType.mpesa,
  openingBalanceMinor: 0,
  openingDate: eat(2026, 11, 1, 0),
);

LedgerEntry draw(int id, DateTime at, int amount, int fee, {int? owed}) =>
    LedgerEntry(
      id: id,
      accountId: mpesa,
      occurredAt: at,
      amountMinor: amount,
      direction: TransactionDirection.inflow,
      kind: TransactionKind.fulizaDraw,
      feeMinor: fee,
      owedAfterMinor: owed,
    );

LedgerEntry repayment(int id, DateTime at, int amount, {int? balance}) =>
    LedgerEntry(
      id: id,
      accountId: mpesa,
      occurredAt: at,
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: TransactionKind.fulizaRepayment,
      balanceAfterMinor: balance,
    );

LedgerEntry received(int id, DateTime at, int amount, {int? balance}) =>
    LedgerEntry(
      id: id,
      accountId: mpesa,
      occurredAt: at,
      amountMinor: amount,
      direction: TransactionDirection.inflow,
      kind: TransactionKind.received,
      counterpartyName: 'EXAMPLE PERSON',
      balanceAfterMinor: balance,
    );

void main() {
  final later = eat(2026, 11, 20);

  group('the M-Pesa sheet in the bug report', () {
    // A payment took M-Pesa to 0, Fuliza covered it (490.07 owed in all),
    // then money came in and M-Pesa repaid Fuliza before crediting the
    // wallet with 6,843.73.
    List<LedgerEntry> base() => [
      entry(
        id: 1,
        at: eat(2026, 11, 13, 18, 40),
        amount: kes(900),
        kind: TransactionKind.paybill,
        balanceAfter: kes(500),
      ),
      entry(
        id: 2,
        at: eat(2026, 11, 13, 19),
        amount: kes(985),
        kind: TransactionKind.paybill,
        balanceAfter: 0,
      ),
      draw(
        3,
        eat(2026, 11, 13, 19).add(const Duration(seconds: 20)),
        48522,
        485,
        owed: 49007,
      ),
      received(4, eat(2026, 11, 14, 8, 19), 733380, balance: 684373),
    ];

    test('with the "fully pay" message: owed 0, wallet 6,843.73', () {
      final entries = [
        ...base(),
        repayment(
          5,
          eat(2026, 11, 14, 8, 19).add(const Duration(seconds: 40)),
          49007,
          balance: 684373,
        ),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(balanceAt(mp, entries, at: later), 684373);
      expect(heldAt(mp, entries, at: later), 684373);
      final check = checkAccount(mp, entries);
      expect(check.gaps, isEmpty);
      expect(check.status, BalanceStatus.matches);
      // The message is the repayment; nothing is worked out on top.
      expect(fulizaDebtAt(mp, entries, at: later).auto, isEmpty);
    });

    test('with the repayment message read before the money in', () {
      final entries = [
        ...base(),
        repayment(5, eat(2026, 11, 14, 8, 18), 49007, balance: 684373),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(balanceAt(mp, entries, at: later), 684373);
      expect(checkAccount(mp, entries).gaps, isEmpty);
    });

    test('without the repayment message: the balance shows it', () {
      final entries = base();
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(balanceAt(mp, entries, at: later), 684373);
      expect(checkAccount(mp, entries).gaps, isEmpty);
      final auto = fulizaDebtAt(mp, entries, at: later).auto.single;
      expect(auto.kind, FulizaAutoKind.repaid);
      expect(auto.amountMinor, 49007);
      expect(auto.entry.id, 4);
    });

    test('a later positive balance clears it with no repayment at all', () {
      final entries = [
        ...base().take(3),
        // A payment message with money left: the repayment happened.
        entry(
          id: 6,
          at: eat(2026, 11, 15, 9),
          amount: kes(50),
          balanceAfter: kes(6000),
        ),
      ];
      expect(fulizaOwedAt(mp, entries, at: eat(2026, 11, 14)), 49007);
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(
        fulizaDebtAt(mp, entries, at: later).auto.single.kind,
        FulizaAutoKind.cleared,
      );
    });

    test('a newer draw after the positive balance is still owed', () {
      final entries = [
        ...base(),
        draw(7, eat(2026, 11, 15, 9), kes(100), 100, owed: kes(101)),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), kes(101));
    });

    test('a "fully pay" timestamped before the total it cleared', () {
      // The draw's message came late, after the repayment.
      final entries = [
        entry(
          id: 1,
          at: eat(2026, 11, 13, 9),
          amount: kes(10),
          balanceAfter: 0,
        ),
        repayment(2, eat(2026, 11, 13, 9, 5), 49007),
        draw(3, eat(2026, 11, 13, 9, 20), 48522, 485, owed: 49007),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), 0);
    });
  });

  group('partial repayments', () {
    test('owed less the repayment, plus later draws and fees', () {
      final entries = [
        draw(1, eat(2026, 11, 10), kes(400), 400, owed: kes(404)),
        repayment(2, eat(2026, 11, 11), kes(100)),
        draw(3, eat(2026, 11, 11, 15), kes(50), 50),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), kes(304) + kes(50) + 50);
    });

    test('money in that all goes to Fuliza leaves the wallet at 0', () {
      final entries = [
        entry(id: 1, at: eat(2026, 11, 10), amount: kes(10), balanceAfter: 0),
        draw(2, eat(2026, 11, 10, 12, 1), kes(400), 400, owed: kes(404)),
        received(3, eat(2026, 11, 11), kes(100), balance: 0),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), kes(304));
      expect(checkAccount(mp, entries).gaps, isEmpty);
    });
  });

  group('the overdraw and the money that repays it', () {
    test('140 held, 280 paid, 150 in: 8.60 left and nothing owed', () {
      final entries = [
        received(1, eat(2026, 11, 16, 9), kes(140), balance: kes(140)),
        // M-Pesa reports 0; no Fuliza message was read.
        entry(
          id: 2,
          at: eat(2026, 11, 16, 10),
          amount: kes(280),
          balanceAfter: 0,
        ),
        received(3, eat(2026, 11, 16, 13), kes(150), balance: 860),
      ];
      expect(fulizaOwedAt(mp, entries, at: eat(2026, 11, 16, 11)), 14140);
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(balanceAt(mp, entries, at: later), 860);
      expect(checkAccount(mp, entries).gaps, isEmpty);
      final auto = fulizaDebtAt(mp, entries, at: later).auto;
      expect(auto.map((a) => a.kind), [
        FulizaAutoKind.drawn,
        FulizaAutoKind.repaid,
      ]);
      expect(auto.first.amountMinor, kes(140));
      expect(auto.first.feeMinor, 140);
      expect(auto.last.amountMinor, 14140);
    });

    test('0 in the wallet with 140 owed, 150 in, 10 left: no gap', () {
      final entries = [
        entry(id: 1, at: eat(2026, 11, 16, 9), amount: kes(5), balanceAfter: 0),
        draw(2, eat(2026, 11, 16, 9, 1), kes(140), 0, owed: kes(140)),
        received(3, eat(2026, 11, 16, 13), kes(150), balance: kes(10)),
      ];
      expect(fulizaOwedAt(mp, entries, at: later), 0);
      expect(balanceAt(mp, entries, at: later), kes(10));
      expect(checkAccount(mp, entries).gaps, isEmpty);
    });

    test('daily charges since the total are a fee in the repayment', () {
      final entries = [
        entry(id: 1, at: eat(2026, 11, 10, 9), amount: kes(5), balanceAfter: 0),
        draw(2, eat(2026, 11, 10, 9, 1), kes(140), 140, owed: 14140),
        // Three days on, M-Pesa takes 141.40 and 3.00 of charges.
        received(3, eat(2026, 11, 13, 9), kes(150), balance: 560),
      ];
      final debt = fulizaDebtAt(mp, entries, at: later);
      expect(debt.owedMinor, 0);
      expect(debt.auto.single.feeMinor, 300);
      expect(debt.charges.fold(0, (s, c) => s + c.amountMinor), 300);
      expect(checkAccount(mp, entries).gaps, isEmpty);
    });

    test('more taken than Fuliza could explain is still a gap', () {
      final entries = [
        entry(id: 1, at: eat(2026, 11, 10, 9), amount: kes(5), balanceAfter: 0),
        draw(2, eat(2026, 11, 10, 9, 1), kes(140), 140, owed: 14140),
        received(3, eat(2026, 11, 10, 13), kes(1000), balance: kes(500)),
      ];
      final gap = checkAccount(mp, entries).gaps.single;
      // 141.40 owed and at most 1.41 of charges went to Fuliza.
      expect(gap.gapMinor, -(kes(1000) - 14281 - kes(500)));
      expect(fulizaOwedAt(mp, entries, at: later), 0);
    });

    test('a bank account never works out Fuliza', () {
      final bank = AccountOpening(
        id: mpesa,
        type: AccountType.bank,
        openingBalanceMinor: 0,
        openingDate: eat(2026, 11, 1, 0),
      );
      final entries = [
        received(1, eat(2026, 11, 16, 9), kes(140), balance: kes(140)),
        entry(
          id: 2,
          at: eat(2026, 11, 16, 10),
          amount: kes(280),
          balanceAfter: 0,
        ),
      ];
      expect(checkAccount(bank, entries).gaps.single.gapMinor, kes(140));
    });
  });

  group('rounding', () {
    test('a gap of 1.00 or less matches; more is shown', () {
      List<LedgerEntry> withBalance(int b) => [
        received(1, eat(2026, 11, 16, 9), kes(100), balance: kes(100)),
        entry(
          id: 2,
          at: eat(2026, 11, 16, 10),
          amount: kes(40),
          balanceAfter: b,
        ),
      ];
      expect(checkAccount(mp, withBalance(kes(59))).gaps, isEmpty);
      expect(checkAccount(mp, withBalance(5899)).gaps.single.gapMinor, -101);
    });
  });

  test('where it went: fees, Fuliza fees and charges, and gaps', () {
    final entries = [
      received(1, eat(2026, 11, 10, 9), kes(100), balance: kes(100)),
      entry(
        id: 2,
        at: eat(2026, 11, 10, 10),
        amount: kes(280),
        fee: kes(7),
        balanceAfter: 0,
      ),
      // Three days on, 3.00 of daily charges too, then 20 we can't explain.
      received(3, eat(2026, 11, 13, 9), kes(400), balance: 20813),
      entry(
        id: 4,
        at: eat(2026, 11, 13, 10),
        amount: kes(10),
        balanceAfter: 17813,
      ),
    ];
    final leaks = whereItWent(
      mp,
      entries,
      checkAccount(mp, entries),
      month: YearMonth(2026, 11),
    );
    expect(leaks.feesMinor, kes(7));
    // Access fee on the 187 Fuliza covered, and 3.00 of daily charges.
    expect(leaks.fulizaMinor, 187 + 300);
    expect(leaks.notExplainedMinor, kes(20));
  });
}
