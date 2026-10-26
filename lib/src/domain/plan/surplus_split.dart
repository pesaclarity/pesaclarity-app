/// Default share of a surplus that goes to debt, in basis points (half).
const defaultDebtShareBasisPoints = 5000;

/// What is left of expected income after the plan, split between paying down
/// debt and saving.
class SurplusSplit {
  const SurplusSplit({
    required this.surplusMinor,
    required this.toDebtMinor,
    required this.toSavingsMinor,
  });

  /// Splits `expectedIncomeMinor - plannedOutgoingMinor`.
  ///
  /// Debt gets [debtShareBasisPoints] of the surplus, rounded down, and
  /// savings get the rest, so the two always add up to the surplus. With no
  /// debt ([hasDebt] false) it all goes to savings. A zero or negative
  /// surplus splits nothing; [shortfallMinor] says how far the plan is over.
  factory SurplusSplit.of({
    required int expectedIncomeMinor,
    required int plannedOutgoingMinor,
    bool hasDebt = true,
    int debtShareBasisPoints = defaultDebtShareBasisPoints,
  }) {
    if (debtShareBasisPoints < 0 || debtShareBasisPoints > 10000) {
      throw ArgumentError.value(
        debtShareBasisPoints,
        'debtShareBasisPoints',
        'must be between 0 and 10000',
      );
    }
    final surplus = expectedIncomeMinor - plannedOutgoingMinor;
    if (surplus <= 0) {
      return SurplusSplit(
        surplusMinor: surplus,
        toDebtMinor: 0,
        toSavingsMinor: 0,
      );
    }
    final toDebt = hasDebt ? surplus * debtShareBasisPoints ~/ 10000 : 0;
    return SurplusSplit(
      surplusMinor: surplus,
      toDebtMinor: toDebt,
      toSavingsMinor: surplus - toDebt,
    );
  }

  /// Negative when the plan spends more than the expected income.
  final int surplusMinor;
  final int toDebtMinor;
  final int toSavingsMinor;

  int get shortfallMinor => surplusMinor < 0 ? -surplusMinor : 0;
}
