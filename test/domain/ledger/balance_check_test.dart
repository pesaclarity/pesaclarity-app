import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balance_check.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import '../fixtures.dart';

const mpesa = 31;
const sacco = 32;
const cash = 33;

AccountOpening opening(int id, AccountType type) => AccountOpening(
  id: id,
  type: type,
  openingBalanceMinor: 0,
  openingDate: eat(2026, 11, 1, 0),
);

LedgerEntry pay(
  int id,
  int amount, {
  required DateTime at,
  int? balance,
  int accountId = mpesa,
  TransactionSource source = TransactionSource.sms,
  TransactionDirection direction = TransactionDirection.outflow,
  int? claimed,
}) => LedgerEntry(
  id: id,
  accountId: accountId,
  occurredAt: at,
  amountMinor: amount,
  direction: direction,
  kind: TransactionKind.till,
  source: source,
  balanceAfterMinor: balance,
  claimedBalanceMinor: claimed,
);

void main() {
  final mp = opening(mpesa, AccountType.mpesa);

  test('reported balances that add up match', () {
    final check = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(5800)),
      pay(2, kes(300), at: eat(2026, 11, 11, 9)),
      pay(3, kes(500), at: eat(2026, 11, 12, 9), balance: kes(5000)),
    ]);
    expect(check.gaps, isEmpty);
    expect(check.status, BalanceStatus.matches);
    expect(check.lastReported!.id, 3);
  });

  test('a statement copy of a message is counted twice and safe to remove', () {
    final check = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(5800)),
      pay(2, kes(1200), at: eat(2026, 11, 11, 9)),
      pay(
        3,
        kes(1200),
        at: eat(2026, 11, 11, 9),
        source: TransactionSource.statement,
      ),
      pay(4, kes(1180), at: eat(2026, 11, 12, 18), balance: kes(3420)),
    ]);
    expect(check.status, BalanceStatus.off);
    final gap = check.latestGap!;
    expect(gap.gapMinor, kes(1200));
    expect(gap.expectedMinor, kes(2220));
    expect(gap.hints.first.cause, GapCause.countedTwice);
    final fix = gap.hints.first.fix! as RemoveCopy;
    expect((fix.entryId, fix.keptId), (3, 2));
  });

  test('two messages with the same amount on one day: named, not removed', () {
    final check = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(5800)),
      pay(2, kes(1200), at: eat(2026, 11, 11, 9)),
      pay(3, kes(1200), at: eat(2026, 11, 11, 15)),
      pay(4, kes(1180), at: eat(2026, 11, 12, 18), balance: kes(3420)),
    ]);
    final hint = check.latestGap!.hints.first;
    expect(hint.cause, GapCause.countedTwice);
    expect(hint.fix, isNull);
  });

  test('a payment under another account can move here', () {
    final sc = opening(sacco, AccountType.sacco);
    final entries = [
      pay(
        1,
        kes(1000),
        at: eat(2026, 11, 2, 9),
        accountId: sacco,
        direction: TransactionDirection.inflow,
        balance: kes(12300),
      ),
      pay(
        2,
        kes(1200),
        at: eat(2026, 11, 3, 9),
        direction: TransactionDirection.inflow,
      ),
      pay(
        3,
        kes(100),
        at: eat(2026, 11, 5, 9),
        accountId: sacco,
        direction: TransactionDirection.inflow,
        balance: kes(13600),
      ),
    ];
    final gap = checkAccount(sc, entries).latestGap!;
    expect(gap.gapMinor, kes(1200));
    final hint = gap.hints.firstWhere((h) => h.cause == GapCause.wrongAccount);
    expect((hint.fix! as MoveHere).entryId, 2);
  });

  test('a payment the wrong way round is named', () {
    final gap = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(1000)),
      pay(2, kes(250), at: eat(2026, 11, 11, 9)),
      pay(3, kes(10), at: eat(2026, 11, 12, 9), balance: kes(1240)),
    ]).latestGap!;
    expect(gap.hints.map((h) => h.cause), contains(GapCause.wrongDirection));
  });

  test('nothing to explain it: probably a missed message', () {
    final gap = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(1000)),
      pay(3, kes(10), at: eat(2026, 11, 12, 9), balance: kes(700)),
    ]).latestGap!;
    expect(gap.hints.single.cause, GapCause.missed);
  });

  test('a correction closes a gap, and a set balance is never a gap', () {
    final entries = [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(1000)),
      LedgerEntry(
        id: 2,
        accountId: mpesa,
        occurredAt: eat(2026, 11, 11, 9),
        amountMinor: kes(290),
        direction: TransactionDirection.outflow,
        kind: TransactionKind.correction,
        source: TransactionSource.manual,
      ),
      pay(3, kes(10), at: eat(2026, 11, 12, 9), balance: kes(700)),
      LedgerEntry(
        id: 4,
        accountId: mpesa,
        occurredAt: eat(2026, 11, 13, 9),
        amountMinor: kes(5000),
        direction: TransactionDirection.inflow,
        kind: TransactionKind.correction,
        source: TransactionSource.manual,
        balanceAfterMinor: kes(5700),
      ),
    ];
    final check = checkAccount(mp, entries);
    expect(check.gaps, isEmpty);
    expect(check.lastCounted, eat(2026, 11, 13, 9));
  });

  test('a claimed balance that does not follow is flagged by name', () {
    final check = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(1000)),
      pay(2, kes(20), at: eat(2026, 11, 11, 9), claimed: kes(38000)),
    ]);
    final gap = check.latestGap!;
    expect(gap.claimed, isTrue);
    expect(gap.to.id, 2);
    expect(gap.hints.single.cause, GapCause.doubtfulBalance);
    expect(check.status, BalanceStatus.off);
  });

  test('a payment Fuliza funded is no gap, though its draw comes after', () {
    final check = checkAccount(mp, [
      pay(1, kes(100), at: eat(2026, 11, 10, 9), balance: kes(200)),
      pay(2, kes(1500), at: eat(2026, 11, 12, 18, 40), balance: 0),
      LedgerEntry(
        id: 3,
        accountId: mpesa,
        occurredAt: eat(2026, 11, 12, 18, 41),
        amountMinor: kes(1300),
        direction: TransactionDirection.inflow,
        kind: TransactionKind.fulizaDraw,
        feeMinor: kes(13),
      ),
      pay(
        4,
        kes(50),
        at: eat(2026, 11, 13, 9),
        balance: kes(50),
        direction: TransactionDirection.inflow,
      ),
    ]);
    expect(check.gaps, isEmpty);
  });

  test('cash with no messages asks to be counted again', () {
    final check = checkAccount(opening(cash, AccountType.cash), const []);
    expect(check.status, BalanceStatus.countAgain);
  });
}
