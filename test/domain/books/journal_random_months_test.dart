import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/journal.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

/// A random synthetic M-Pesa month from [seed]: payments, money in, Fuliza
/// draws (some with totals), repayments and corrections, with reported,
/// claimed and missing balances, often minutes apart.
List<LedgerEntry> randomMonth(int seed, DateTime start) {
  final r = Random(seed);
  var t = start;
  final kinds = [
    ...List.filled(4, TransactionKind.till),
    ...List.filled(2, TransactionKind.received),
    ...List.filled(2, TransactionKind.fulizaDraw),
    TransactionKind.fulizaRepayment,
    TransactionKind.correction,
  ];
  const gaps = [1, 3, 8, 20, 300, 1500];
  return [
    for (var id = 1; id <= 30; id++)
      () {
        t = t.add(Duration(minutes: gaps[r.nextInt(gaps.length)]));
        final kind = kinds[r.nextInt(kinds.length)];
        final inflow =
            kind == TransactionKind.received ||
            kind == TransactionKind.fulizaDraw ||
            (kind == TransactionKind.correction && r.nextBool());
        final amount = (r.nextInt(50) + 1) * 1000;
        final balance = kind == TransactionKind.correction
            ? (r.nextInt(80) - 20) * 1000
            : r.nextInt(4) == 0
            ? 0
            : r.nextInt(80) * 1000;
        return LedgerEntry(
          id: id,
          accountId: 1,
          occurredAt: t,
          amountMinor: amount,
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: kind,
          feeMinor: kind == TransactionKind.fulizaDraw ? fulizaFee(amount) : 0,
          balanceAfterMinor: r.nextInt(4) == 0 ? null : balance,
          claimedBalanceMinor: r.nextInt(6) == 0 ? balance : null,
          owedAfterMinor: kind == TransactionKind.fulizaDraw && r.nextBool()
              ? amount + r.nextInt(3000)
              : null,
        );
      }(),
  ];
}

int fulizaFee(int amount) => (amount + 50) ~/ 100;

void main() {
  final start = DateTime.utc(2026, 11);
  final mpesa = AccountOpening(
    id: 1,
    type: AccountType.mpesa,
    openingBalanceMinor: 100000,
    openingDate: start,
  );

  test('on random messy months the journal balances, its M-Pesa equals the '
      'balance code after every entry, and Fuliza owed equals it once '
      'every record is in', () {
    final off = <String>[];
    for (var seed = 0; seed < 200; seed++) {
      final history = randomMonth(seed, start);
      final journal = postJournal(
        accounts: [mpesa],
        history: history,
        categories: const {},
      );
      for (final e in journal) {
        expect(e.lines.fold(0, (s, l) => s + l.amountMinor), 0, reason: '$e');
      }
      for (final e in history) {
        final at = e.occurredAt.add(const Duration(seconds: 1));
        final money = journalBalance(
          journal,
          const BookAccount.money(1),
          currency: 'KES',
          at: at,
        );
        if (money != balanceAt(mpesa, history, at: at)) {
          off.add('seed $seed, wallet after ${e.id}');
        }
      }
      final end = history.last.occurredAt.add(const Duration(days: 1));
      final owed = journalBalance(
        journal,
        const BookAccount.fulizaOwed(1),
        currency: 'KES',
        at: end,
      );
      if (owed != fulizaOwedAt(mpesa, history, at: end)) {
        off.add('seed $seed, Fuliza owed at the end');
      }
    }
    expect(off, isEmpty);
  });
}
