import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/journal_balances.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/leakage.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza_terms.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import '../../helpers/balance_oracle.dart' as oracle;
import '../fixtures.dart';
import 'journal_test.dart' as month;

final mpesa = AccountOpening(
  id: 1,
  type: AccountType.mpesa,
  openingBalanceMinor: kes(300),
  openingDate: eat(2026, 11, 1, 0),
);

LedgerEntry mp(
  int id,
  DateTime at,
  int amount, {
  bool inflow = false,
  TransactionKind kind = TransactionKind.till,
  int fee = 0,
  int? balance,
  int? claimed,
  int? owedAfter,
}) => LedgerEntry(
  id: id,
  accountId: 1,
  occurredAt: at,
  amountMinor: amount,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: kind,
  feeMinor: fee,
  balanceAfterMinor: balance,
  claimedBalanceMinor: claimed,
  owedAfterMinor: owedAfter,
);

void main() {
  group('a Fuliza draw that funded a payment whose balance was a claim left '
      'out', () {
    // 300 in the wallet, a 1,300 payment; its balance, typed while checking
    // the message, says 500, which does not follow, so it is left out.
    // Fuliza's message two minutes later lent the 1,000 that paid for it.
    final history = [
      mp(1, eat(2026, 11, 2, 9), kes(100), balance: kes(200)),
      mp(2, eat(2026, 11, 6), kes(1300), claimed: kes(500)),
      mp(
        3,
        eat(2026, 11, 6, 12, 2),
        kes(1000),
        inflow: true,
        kind: TransactionKind.fulizaDraw,
        fee: kes(10),
        owedAfter: kes(1010),
      ),
    ];
    final journal = JournalBalances.ofRecords([mpesa], history);
    final after = eat(2026, 11, 7);

    test('counts the draw: 100 short, not 1,100', () {
      // 200 - 1,300 + 1,000 lent.
      expect(journal.walletAt(mpesa, at: after), -kes(100));
      expect(journal.fulizaOwedAt(mpesa, at: after), kes(1010));
      expect(journal.heldAt(mpesa, at: after), -kes(1110));
      // Nothing is left in transit: the draw reached the payment.
      expect(
        journal.balanceOf(
          BookAccount.moneyInTransit,
          currency: 'KES',
          at: after,
        ),
        0,
      );
    });

    test('where the old balance code lost the draw', () {
      expect(oracle.balanceAt(mpesa, history, at: after), -kes(1100));
    });
  });

  test('Fuliza owed at a past instant is what the whole history says', () {
    // 1,010 owed; money in shows 2,000 in the wallet, and a repayment
    // message follows five minutes later, as on a statement.
    final history = [
      mp(1, eat(2026, 11, 2, 9), kes(1300), balance: 0),
      mp(
        2,
        eat(2026, 11, 2, 9, 1),
        kes(1000),
        inflow: true,
        kind: TransactionKind.fulizaDraw,
        fee: kes(10),
        owedAfter: kes(1010),
      ),
      mp(
        3,
        eat(2026, 11, 3, 10),
        kes(2000),
        inflow: true,
        kind: TransactionKind.received,
        balance: kes(2000),
      ),
      mp(
        4,
        eat(2026, 11, 3, 10, 5),
        kes(1010),
        kind: TransactionKind.fulizaRepayment,
        balance: kes(990),
      ),
    ];
    final journal = JournalBalances.ofRecords([mpesa], history);
    final between = eat(2026, 11, 3, 10, 2);
    // Until the repayment, Fuliza is still owed: the money in had not
    // been taken for it yet.
    expect(journal.fulizaOwedAt(mpesa, at: between), kes(1010));
    expect(journal.heldAt(mpesa, at: between), kes(990));
    // The old code read only what came before, took the 2,000 to mean
    // Fuliza was clear, and said it was worth 2,000 then.
    expect(oracle.fulizaOwedAt(mpesa, history, at: between), 0);
    // Afterwards both agree.
    final later = eat(2026, 11, 4);
    expect(journal.fulizaOwedAt(mpesa, at: later), 0);
    expect(journal.walletAt(mpesa, at: later), kes(990));
  });

  test('Fuliza terms come from one place', () {
    expect(fulizaTerms.accessFee(kes(1000)), kes(10));
    expect(fulizaTerms.accessFee(kes(559)), 559);
    expect(fulizaTerms.accessFee(149), 1);
    // 1% a day, at least 1.00 a day.
    expect(fulizaTerms.chargeAllowance(kes(1515), 4), 6060);
    expect(fulizaTerms.chargeAllowance(kes(50), 3), kes(3));
    expect(fulizaTerms.chargeAllowance(kes(50000), 2), kes(1000));
    expect(fulizaTerms.chargeAllowance(kes(50000), 0), kes(500));
  });

  test('Insights count Fuliza charges the balances show, from the journal', () {
    final history = month.messyMonth();
    final journal = JournalBalances.ofRecords(
      month.accounts,
      history,
      categories: month.categories,
    );
    final from = eat(2026, 11, 1, 0);
    final to = eat(2026, 12, 1, 0);
    final withJournal = LeakageBreakdown.of(
      history,
      from: from,
      to: to,
      journal: journal,
    );
    // Access fees 10 and 6 from the draw messages, 5 on the draw no message
    // showed, and 15 of daily charges M-Pesa kept from the salary.
    expect(withJournal.fulizaMinor, kes(10 + 6 + 5 + 15));
    final messagesOnly = LeakageBreakdown.of(history, from: from, to: to);
    // Without the journal the 5 and the 15 were missed.
    expect(withJournal.totalMinor - messagesOnly.totalMinor, kes(5 + 15));
  });
}
