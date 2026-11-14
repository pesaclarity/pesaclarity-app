import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';

import '../fixtures.dart';

const kcb = 21;
const mpesa = 22;

LedgerEntry out(int id, int amount, {int fee = 0, int minute = 0, int? to}) =>
    LedgerEntry(
      id: id,
      accountId: kcb,
      occurredAt: eat(2026, 11, 14, 10, minute),
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: TransactionKind.bank,
      feeMinor: fee,
      transferAccountId: to,
    );

LedgerEntry into(
  int id,
  int amount, {
  DateTime? at,
  int minute = 2,
  TransactionSource source = TransactionSource.sms,
}) => LedgerEntry(
  id: id,
  accountId: mpesa,
  occurredAt: at ?? eat(2026, 11, 14, 10, minute),
  amountMinor: amount,
  direction: TransactionDirection.inflow,
  kind: TransactionKind.received,
  source: source,
);

void main() {
  group('fee tolerance', () {
    test('pairs when the outflow is larger by its own fee', () {
      expect(
        findOwnTransfers([out(1, kes(5030), fee: kes(30)), into(2, kes(5000))]),
        [const TransferPair(1, 2)],
      );
    });

    test('not when the difference is more than its own fee', () {
      expect(
        findOwnTransfers([out(1, kes(5050), fee: kes(30)), into(2, kes(5000))]),
        isEmpty,
      );
    });

    test('without a fee, up to KES 100 or 2%', () {
      expect(
        findOwnTransfers([out(1, kes(5000)), into(2, kes(4900))]),
        hasLength(1),
      );
      expect(
        findOwnTransfers([out(1, kes(5000)), into(2, kes(4899))]),
        isEmpty,
      );
      // 2% of 20,000 is 400.
      expect(
        findOwnTransfers([out(1, kes(20400)), into(2, kes(20000))]),
        hasLength(1),
      );
    });

    test('equal amounts pair before a fee-sized difference', () {
      final pairs = findOwnTransfers([
        out(1, kes(5000)),
        into(2, kes(4970), minute: 1),
        into(3, kes(5000), minute: 20),
      ]);
      expect(pairs, [const TransferPair(1, 3)]);
    });
  });

  group('window', () {
    test('30 minutes for an automatic pair', () {
      expect(
        findOwnTransfers([out(1, kes(500)), into(2, kes(500), minute: 31)]),
        isEmpty,
      );
    });

    test('a transfer the person named waits up to 3 days for its side', () {
      final named = out(1, kes(500), to: mpesa);
      expect(
        findOwnTransfers([named, into(2, kes(500), at: eat(2026, 11, 16, 9))]),
        [const TransferPair(1, 2)],
      );
      expect(
        findOwnTransfers([named, into(2, kes(500), at: eat(2026, 11, 18, 10))]),
        isEmpty,
      );
      expect(roleOf(named), LedgerRole.ownTransfer);
    });

    test('a named transfer pairs only with the account named', () {
      expect(
        findOwnTransfers([out(1, kes(500), to: 99), into(2, kes(500))]),
        isEmpty,
      );
    });

    test('money typed in by hand never pairs by itself', () {
      expect(
        findOwnTransfers([
          out(1, kes(500)),
          into(2, kes(500), source: TransactionSource.manual),
        ]),
        isEmpty,
      );
    });

    test('a pair the person unmatched never pairs again', () {
      expect(
        findOwnTransfers(
          [out(1, kes(500)), into(2, kes(500))],
          declined: {const TransferPair(1, 2)},
        ),
        isEmpty,
      );
    });
  });

  group('suggestions', () {
    test('offers candidates up to 3 days away, best first', () {
      final money = into(1, kes(5000));
      final suggestions = suggestTransferPartners(money, [
        money,
        out(2, kes(5030)),
        LedgerEntry(
          id: 3,
          accountId: kcb,
          occurredAt: eat(2026, 11, 12, 10),
          amountMinor: kes(5000),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.bank,
        ),
        // Too far.
        LedgerEntry(
          id: 4,
          accountId: kcb,
          occurredAt: eat(2026, 11, 9, 10),
          amountMinor: kes(5000),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.bank,
        ),
        // A till payment is never a transfer.
        LedgerEntry(
          id: 5,
          accountId: kcb,
          occurredAt: eat(2026, 11, 14, 10),
          amountMinor: kes(5000),
          direction: TransactionDirection.outflow,
          kind: TransactionKind.till,
        ),
      ]);
      expect(suggestions.map((s) => s.partner.id), [3, 2]);
      expect(suggestions.last.feeMinor(money.amountMinor), kes(30));
    });

    test('nothing for a paired entry', () {
      final paired = into(1, kes(5000)).copyWith(transferPairId: 9);
      expect(suggestTransferPartners(paired, [out(2, kes(5000))]), isEmpty);
    });
  });
}
