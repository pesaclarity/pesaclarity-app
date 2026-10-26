import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';

import '../fixtures.dart';

const bank = 11;
const mpesa = 12;
const mmf = 13;

void main() {
  group('findOwnTransfers', () {
    test('pairs bank to own M-Pesa', () {
      final out = entry(
        id: 10,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5, 9),
        amount: kes(5000),
      );
      final into = inflow(
        id: 11,
        accountId: mpesa,
        at: eat(2026, 10, 5, 9, 2),
        amount: kes(5000),
      );
      expect(findOwnTransfers([out, into]), [const TransferPair(10, 11)]);
    });

    test('pairs M-Pesa paybill to bank when the bank message comes first', () {
      final into = inflow(
        id: 20,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5, 9),
        amount: kes(12000),
      );
      final out = entry(
        id: 21,
        accountId: mpesa,
        kind: TransactionKind.paybill,
        at: eat(2026, 10, 5, 9, 20),
        amount: kes(12000),
      );
      expect(findOwnTransfers([into, out]), [const TransferPair(21, 20)]);
    });

    test('pairs across Nairobi midnight', () {
      final out = entry(
        id: 1,
        accountId: mpesa,
        kind: TransactionKind.paybill,
        at: eat(2026, 10, 31, 23, 55),
        amount: kes(3000),
      );
      final into = inflow(
        id: 2,
        accountId: mmf,
        kind: TransactionKind.bank,
        at: eat(2026, 11, 1, 0, 10),
        amount: kes(3000),
      );
      expect(findOwnTransfers([out, into]), hasLength(1));
    });

    test('leaves non-matching entries alone', () {
      final out = entry(
        id: 1,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5, 9),
        amount: kes(5000),
      );
      final candidates = [
        // Same account.
        inflow(
          id: 2,
          accountId: bank,
          at: eat(2026, 10, 5, 9, 1),
          amount: kes(5000),
        ),
        // Different amount.
        inflow(
          id: 3,
          accountId: mpesa,
          at: eat(2026, 10, 5, 9, 1),
          amount: kes(4999),
        ),
        // Too late.
        inflow(
          id: 4,
          accountId: mpesa,
          at: eat(2026, 10, 5, 9, 31),
          amount: kes(5000),
        ),
        // Different currency.
        inflow(
          id: 5,
          accountId: mpesa,
          at: eat(2026, 10, 5, 9, 1),
          amount: kes(5000),
          currency: 'USD',
        ),
        // Named as income by the user.
        inflow(
          id: 6,
          accountId: mpesa,
          at: eat(2026, 10, 5, 9, 1),
          amount: kes(5000),
          payeeId: 7,
          categoryType: CategoryType.income,
        ),
        // Not a transfer kind.
        inflow(
          id: 7,
          accountId: mpesa,
          kind: TransactionKind.reversal,
          at: eat(2026, 10, 5, 9, 1),
          amount: kes(5000),
        ),
      ];
      expect(findOwnTransfers([out, ...candidates]), isEmpty);
    });

    test('never pairs till payments, airtime or withdrawals', () {
      for (final kind in [
        TransactionKind.till,
        TransactionKind.airtime,
        TransactionKind.withdrawal,
      ]) {
        final out = entry(
          id: 1,
          accountId: mpesa,
          kind: kind,
          at: eat(2026, 10, 5),
          amount: kes(100),
        );
        final into = inflow(
          id: 2,
          accountId: bank,
          at: eat(2026, 10, 5),
          amount: kes(100),
        );
        expect(findOwnTransfers([out, into]), isEmpty, reason: kind.name);
      }
    });

    test('pairs closest in time first and uses each entry once', () {
      final outA = entry(
        id: 1,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5, 9),
        amount: kes(1000),
      );
      final outB = entry(
        id: 2,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5, 9, 10),
        amount: kes(1000),
      );
      final inA = inflow(
        id: 3,
        accountId: mpesa,
        at: eat(2026, 10, 5, 9, 1),
        amount: kes(1000),
      );
      final inB = inflow(
        id: 4,
        accountId: mpesa,
        at: eat(2026, 10, 5, 9, 11),
        amount: kes(1000),
      );

      final expected = {const TransferPair(1, 3), const TransferPair(2, 4)};
      expect(findOwnTransfers([outA, outB, inA, inB]).toSet(), expected);
      expect(findOwnTransfers([inB, inA, outB, outA]).toSet(), expected);
    });

    test('skips entries that are already paired', () {
      final out = entry(
        id: 1,
        accountId: bank,
        kind: TransactionKind.bank,
        at: eat(2026, 10, 5),
        amount: kes(100),
        transferPairId: 99,
      );
      final into = inflow(
        id: 2,
        accountId: mpesa,
        at: eat(2026, 10, 5),
        amount: kes(100),
      );
      expect(findOwnTransfers([out, into]), isEmpty);
    });
  });

  test('paired transfers are never spending, but their fees are', () {
    final out = entry(
      id: 1,
      accountId: mpesa,
      kind: TransactionKind.paybill,
      at: eat(2026, 10, 5, 9),
      amount: kes(10000),
      fee: kes(57),
    );
    final into = inflow(
      id: 2,
      accountId: bank,
      kind: TransactionKind.bank,
      at: eat(2026, 10, 5, 9, 1),
      amount: kes(10000),
    );
    final linked = applyTransferPairs([
      out,
      into,
    ], findOwnTransfers([out, into]));

    expect(linked.map((e) => e.transferPairId), [2, 1]);
    expect(linked.map(roleOf), everyElement(LedgerRole.ownTransfer));

    final totals = LedgerTotals.of(
      linked,
      from: eat(2026, 10, 1, 0),
      to: eat(2026, 11, 1, 0),
    );
    expect(totals.spendingMinor, 0);
    expect(totals.incomeMinor, 0);
    expect(totals.ownTransferMinor, kes(10000));
    expect(totals.feesMinor, kes(57));
  });
}
