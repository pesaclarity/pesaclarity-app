import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final at = eat(2026, 10, 5);

  group('money received from people', () {
    test('stays neutral until the payee is named', () {
      final unnamed = inflow(at: at, amount: kes(2000));
      expect(roleOf(unnamed), LedgerRole.awaitingPayee);
      expect(needsPayeeName(unnamed), isTrue);
      expect(neutralRoles, contains(LedgerRole.awaitingPayee));
    });

    test('follows the named payee category', () {
      expect(
        roleOf(
          inflow(
            at: at,
            amount: 1,
            payeeId: 1,
            categoryType: CategoryType.income,
          ),
        ),
        LedgerRole.income,
      );
      expect(
        roleOf(
          inflow(
            at: at,
            amount: 1,
            payeeId: 1,
            categoryType: CategoryType.debt,
          ),
        ),
        LedgerRole.borrowing,
      );
      expect(
        roleOf(
          inflow(
            at: at,
            amount: 1,
            payeeId: 1,
            categoryType: CategoryType.transfer,
          ),
        ),
        LedgerRole.ownTransfer,
      );
      final namedNoCategory = inflow(at: at, amount: 1, payeeId: 1);
      expect(roleOf(namedNoCategory), LedgerRole.income);
      expect(needsPayeeName(namedNoCategory), isFalse);
    });

    test('a salary credit at the bank is income even unnamed', () {
      expect(
        roleOf(inflow(kind: TransactionKind.bank, at: at, amount: 1)),
        LedgerRole.income,
      );
    });
  });

  group('outflows', () {
    test('count by category type', () {
      expect(roleOf(entry(at: at, amount: 1)), LedgerRole.spending);
      expect(
        roleOf(entry(at: at, amount: 1, categoryType: CategoryType.debt)),
        LedgerRole.debtRepayment,
      );
      expect(
        roleOf(entry(at: at, amount: 1, categoryType: CategoryType.savings)),
        LedgerRole.saving,
      );
      expect(
        roleOf(entry(at: at, amount: 1, categoryType: CategoryType.tax)),
        LedgerRole.tax,
      );
    });

    test('unknown numbers ask for a name; tills do not', () {
      expect(
        needsPayeeName(entry(kind: TransactionKind.sent, at: at, amount: 1)),
        isTrue,
      );
      expect(needsPayeeName(entry(at: at, amount: 1)), isFalse);
      expect(
        needsPayeeName(
          entry(
            kind: TransactionKind.sent,
            at: at,
            amount: 1,
            transferPairId: 9,
          ),
        ),
        isFalse,
      );
    });

    test('noise kinds have fixed roles', () {
      expect(
        roleOf(entry(kind: TransactionKind.charge, at: at, amount: 1)),
        LedgerRole.fee,
      );
      expect(
        roleOf(entry(kind: TransactionKind.roundUp, at: at, amount: 1)),
        LedgerRole.ownTransfer,
      );
      expect(
        roleOf(inflow(kind: TransactionKind.fulizaDraw, at: at, amount: 1)),
        LedgerRole.borrowing,
      );
      expect(
        roleOf(entry(kind: TransactionKind.fulizaRepayment, at: at, amount: 1)),
        LedgerRole.debtRepayment,
      );
      expect(
        roleOf(inflow(kind: TransactionKind.reversal, at: at, amount: 1)),
        LedgerRole.reversal,
      );
    });
  });

  group('LedgerTotals', () {
    final october = YearMonth(2026, 10);

    test('sums one Nairobi month honestly', () {
      final entries = [
        inflow(
          kind: TransactionKind.bank,
          at: eat(2026, 10, 1, 0),
          amount: kes(80000),
        ),
        inflow(at: eat(2026, 10, 2), amount: kes(3000)),
        entry(at: eat(2026, 10, 3), amount: kes(1200), fee: kes(7)),
        entry(
          kind: TransactionKind.charge,
          at: eat(2026, 10, 4),
          amount: kes(55),
        ),
        inflow(
          kind: TransactionKind.reversal,
          at: eat(2026, 10, 5),
          amount: kes(200),
        ),
        entry(
          at: eat(2026, 10, 6),
          amount: kes(500),
          categoryType: CategoryType.savings,
        ),
        entry(
          at: eat(2026, 10, 7),
          amount: kes(900),
          categoryType: CategoryType.tax,
        ),
        // Just outside the month on either side.
        entry(at: eat(2026, 9, 30, 23, 59), amount: kes(999)),
        entry(at: eat(2026, 11, 1, 0), amount: kes(999)),
        // Another currency.
        entry(at: eat(2026, 10, 8), amount: 5000, currency: 'USD'),
      ];
      final totals = LedgerTotals.of(
        entries,
        from: october.startInstant,
        to: october.endInstant,
      );
      expect(totals.incomeMinor, kes(80000));
      expect(totals.awaitingPayeeMinor, kes(3000));
      expect(totals.spendingMinor, kes(1000));
      expect(totals.feesMinor, kes(62));
      expect(totals.savingMinor, kes(500));
      expect(totals.taxMinor, kes(900));
    });

    test('an empty ledger is all zeros', () {
      final totals = LedgerTotals.of(
        [],
        from: october.startInstant,
        to: october.endInstant,
      );
      expect(totals.incomeMinor + totals.spendingMinor + totals.feesMinor, 0);
    });
  });
}
