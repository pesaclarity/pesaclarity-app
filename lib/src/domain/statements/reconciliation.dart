import '../enums.dart';

/// One ledger transaction's effect on the account balance.
class BalanceMove {
  const BalanceMove({
    required this.amountMinor,
    required this.direction,
    this.feeMinor = 0,
  });

  final int amountMinor;
  final TransactionDirection direction;
  final int feeMinor;

  int get netMinor =>
      (direction == TransactionDirection.inflow ? amountMinor : -amountMinor) -
      feeMinor;
}

/// How the ledger compares with a statement over the statement's period.
class Reconciliation {
  const Reconciliation({
    required this.openingBalanceMinor,
    required this.closingBalanceMinor,
    required this.ledgerClosingMinor,
  });

  /// Works out the ledger's closing balance from the statement's opening
  /// balance and every ledger [moves] in the period, including those added
  /// from the statement and those already there from SMS.
  factory Reconciliation.of({
    required int openingBalanceMinor,
    required int closingBalanceMinor,
    required Iterable<BalanceMove> moves,
  }) => Reconciliation(
    openingBalanceMinor: openingBalanceMinor,
    closingBalanceMinor: closingBalanceMinor,
    ledgerClosingMinor: moves.fold(
      openingBalanceMinor,
      (sum, move) => sum + move.netMinor,
    ),
  );

  final int openingBalanceMinor;

  /// The statement's closing balance.
  final int closingBalanceMinor;

  /// The balance the ledger reaches at the end of the period.
  final int ledgerClosingMinor;

  /// Statement closing balance minus the ledger's; zero when they agree.
  /// Positive means the ledger is missing money in, negative money out.
  int get gapMinor => closingBalanceMinor - ledgerClosingMinor;

  StatementImportResult get result => gapMinor == 0
      ? StatementImportResult.reconciled
      : StatementImportResult.gap;
}
