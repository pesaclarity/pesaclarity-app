import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/statements/reconciliation.dart';

void main() {
  const moves = [
    BalanceMove(amountMinor: 200000, direction: TransactionDirection.inflow),
    BalanceMove(
      amountMinor: 150000,
      direction: TransactionDirection.outflow,
      feeMinor: 1500,
    ),
  ];

  test('reconciles when the ledger reaches the closing balance', () {
    final r = Reconciliation.of(
      openingBalanceMinor: 500000,
      closingBalanceMinor: 548500,
      moves: moves,
    );
    expect(r.ledgerClosingMinor, 548500);
    expect(r.gapMinor, 0);
    expect(r.result, StatementImportResult.reconciled);
  });

  test('shows the gap when money is missing', () {
    final r = Reconciliation.of(
      openingBalanceMinor: 500000,
      closingBalanceMinor: 538500,
      moves: moves,
    );
    expect(r.gapMinor, -10000);
    expect(r.result, StatementImportResult.gap);
  });
}
