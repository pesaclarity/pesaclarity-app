import '../debts/debt.dart';

/// How far the user has come on one debt.
class DebtLine {
  const DebtLine(this.debt, this.originalMinor);

  final Debt debt;

  /// What was owed at the start, or what is owed now if that is more.
  final int originalMinor;

  int get paidMinor => originalMinor - debt.balanceMinor;

  bool get isCleared => debt.balanceMinor == 0;

  /// Paid over original, from 0 to 1.
  double get paidFraction => originalMinor == 0 ? 1 : paidMinor / originalMinor;
}

/// Progress across every debt, for the debt-free card on Goals.
class DebtProgress {
  const DebtProgress._(this.lines);

  /// [startingBalances] maps a debt id to what was first owed on it.
  factory DebtProgress.of(
    Iterable<Debt> debts,
    Map<int, int> startingBalances,
  ) => DebtProgress._([
    for (final debt in debts)
      DebtLine(debt, _atLeast(startingBalances[debt.id], debt.balanceMinor)),
  ]);

  /// Every debt, in the order given.
  final List<DebtLine> lines;

  /// The debts with something still owed.
  List<DebtLine> get open => [
    for (final line in lines)
      if (!line.isCleared) line,
  ];

  int get count => lines.length;

  int get clearedCount => lines.where((l) => l.isCleared).length;

  int get remainingMinor =>
      lines.fold(0, (sum, l) => sum + l.debt.balanceMinor);

  int get originalMinor => lines.fold(0, (sum, l) => sum + l.originalMinor);

  /// Paid over original across every debt, from 0 to 1.
  double get paidFraction {
    final original = originalMinor;
    return original == 0 ? 1 : (original - remainingMinor) / original;
  }
}

int _atLeast(int? starting, int now) =>
    starting == null || starting < now ? now : starting;
