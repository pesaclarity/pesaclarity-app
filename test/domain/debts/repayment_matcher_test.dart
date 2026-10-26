import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/repayment_matcher.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/payees/payee_identifier.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

final debts = [
  Debt(
    id: 1,
    lender: 'Test Bank',
    type: DebtType.bankLoan,
    balanceMinor: kes(100000),
    annualRateBasisPoints: 1400,
    minimumPaymentMinor: kes(5000),
    payeeId: 7,
  ),
  Debt(
    id: 2,
    lender: 'Mama Test',
    type: DebtType.family,
    balanceMinor: kes(6000),
    instalments: [
      DebtInstalment(
        dueDate: CalendarDate(2026, 11, 30),
        amountMinor: kes(2000),
      ),
    ],
  ),
  Debt(id: 3, lender: 'Fuliza', type: DebtType.fuliza, balanceMinor: kes(500)),
  Debt(
    id: 4,
    lender: 'Test SACCO',
    type: DebtType.saccoLoan,
    balanceMinor: kes(40000),
    minimumPaymentMinor: kes(3000),
    identifiers: [PayeeIdentifier.paybill('400200')!],
  ),
];

LedgerEntry paid(
  int id,
  int amount, {
  int? payeeId,
  String? payeeName,
  TransactionDirection direction = TransactionDirection.outflow,
  TransactionKind kind = TransactionKind.paybill,
  int? transferPairId,
  String currency = 'KES',
}) => LedgerEntry(
  id: id,
  accountId: 1,
  occurredAt: eat(2026, 11, 28),
  amountMinor: amount,
  direction: direction,
  kind: kind,
  payeeId: payeeId,
  payeeName: payeeName,
  transferPairId: transferPairId,
  currency: currency,
);

Map<int, (int, RepaymentMatch)> suggest(
  List<RepaymentCandidate> candidates, {
  Set<int> linked = const {},
}) => {
  for (final s in suggestRepayments(
    debts: debts,
    candidates: candidates,
    linkedEntryIds: linked,
  ))
    s.entryId: (s.debtId, s.match),
};

void main() {
  test('matches by payee, within the amount tolerance', () {
    expect(
      suggest([
        RepaymentCandidate(paid(10, kes(5400), payeeId: 7)),
        RepaymentCandidate(paid(11, kes(4500), payeeId: 7)),
        RepaymentCandidate(paid(12, kes(9000), payeeId: 7)),
      ]),
      {
        10: (1, RepaymentMatch.payeeAndAmount),
        11: (1, RepaymentMatch.payeeAndAmount),
        12: (1, RepaymentMatch.payeeOnly),
      },
    );
  });

  test('the tolerance edge is inclusive', () {
    expect(
      suggestRepayments(
        debts: debts,
        candidates: [RepaymentCandidate(paid(10, kes(5500), payeeId: 7))],
      ).single.match,
      RepaymentMatch.payeeAndAmount,
    );
    expect(
      suggestRepayments(
        debts: debts,
        candidates: [RepaymentCandidate(paid(10, kes(5500) + 1, payeeId: 7))],
      ).single.match,
      RepaymentMatch.payeeOnly,
    );
  });

  test('matches by payee name containing the lender, and by instalment', () {
    expect(
      suggest([
        RepaymentCandidate(
          paid(
            20,
            kes(2000),
            payeeName: 'MAMA  TEST',
            kind: TransactionKind.sent,
          ),
        ),
        RepaymentCandidate(paid(21, kes(700), payeeName: 'Test Bank Loans')),
        RepaymentCandidate(paid(22, kes(2000), payeeName: 'Mama Testing')),
      ]),
      {
        20: (2, RepaymentMatch.payeeAndAmount),
        21: (1, RepaymentMatch.payeeOnly),
      },
    );
  });

  test('matches by counterparty identifier', () {
    expect(
      suggest([
        RepaymentCandidate(
          paid(30, kes(3000)),
          counterparty: PayeeIdentifier.paybill('400200', 'MEMBER 12'),
        ),
        RepaymentCandidate(
          paid(31, kes(3000)),
          counterparty: PayeeIdentifier.paybill('400201', 'MEMBER 12'),
        ),
      ]),
      {30: (4, RepaymentMatch.payeeAndAmount)},
    );
  });

  test('Fuliza repayments go to the Fuliza debt; draws are ignored', () {
    expect(
      suggest([
        RepaymentCandidate(
          paid(40, kes(505), kind: TransactionKind.fulizaRepayment),
        ),
        RepaymentCandidate(
          paid(
            41,
            kes(500),
            kind: TransactionKind.fulizaDraw,
            direction: TransactionDirection.inflow,
          ),
        ),
      ]),
      {40: (3, RepaymentMatch.fuliza)},
    );
  });

  test('skips inflows, own transfers, other currencies and linked entries', () {
    expect(
      suggest(
        [
          RepaymentCandidate(
            paid(
              50,
              kes(5000),
              payeeId: 7,
              direction: TransactionDirection.inflow,
            ),
          ),
          RepaymentCandidate(
            paid(51, kes(5000), payeeId: 7, transferPairId: 99),
          ),
          RepaymentCandidate(paid(52, 5000, payeeId: 7, currency: 'USD')),
          RepaymentCandidate(paid(53, kes(5000), payeeId: 7)),
          RepaymentCandidate(paid(54, kes(5000), payeeId: 8)),
        ],
        linked: {53},
      ),
      isEmpty,
    );
  });

  test('when two debts match, the closer amount wins', () {
    final twin = Debt(
      id: 5,
      lender: 'Test Bank',
      type: DebtType.card,
      balanceMinor: kes(20000),
      minimumPaymentMinor: kes(1000),
      payeeId: 7,
    );
    final result = suggestRepayments(
      debts: [...debts, twin],
      candidates: [
        RepaymentCandidate(paid(60, kes(1050), payeeId: 7)),
        RepaymentCandidate(paid(61, kes(4800), payeeId: 7)),
        RepaymentCandidate(paid(62, kes(2500), payeeId: 7)),
      ],
    );
    expect(
      {for (final s in result) s.entryId: (s.debtId, s.match)},
      {
        60: (5, RepaymentMatch.payeeAndAmount),
        61: (1, RepaymentMatch.payeeAndAmount),
        62: (5, RepaymentMatch.payeeOnly),
      },
    );
  });
}
