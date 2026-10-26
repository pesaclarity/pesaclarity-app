import '../time/calendar.dart';
import 'debt.dart';
import 'payoff_order.dart';

/// One debt's share of a payday.
class PaydayShare {
  const PaydayShare({
    required this.debtId,
    required this.minimumMinor,
    required this.extraMinor,
  });

  final int debtId;

  /// Towards the scheduled payment.
  final int minimumMinor;

  /// On top, because this debt is the target.
  final int extraMinor;

  int get totalMinor => minimumMinor + extraMinor;
}

/// What this payday sends to each debt: scheduled payments first, then the
/// rest to the target debt the strategy picks, and on down the order if the
/// target clears.
class PaydaySplit {
  const PaydaySplit._({
    required this.shares,
    required this.targetDebtId,
    required this.unallocatedMinor,
    required this.shortfallMinor,
  });

  /// Splits [availableMinor] for debts this payday, in [month]. Scheduled
  /// payments include missed family instalments. When the money does not
  /// cover every scheduled payment, they are met in payoff order and
  /// [shortfallMinor] says how much is missing.
  factory PaydaySplit.of({
    required Iterable<Debt> debts,
    required int availableMinor,
    required YearMonth month,
    PayoffStrategy strategy = PayoffStrategy.avalanche,
    List<int> customOrder = const [],
    int? firstDebtId,
  }) {
    final ordered = payoffOrder(
      [
        for (final d in debts)
          if (d.balanceMinor > 0) d,
      ],
      strategy,
      customOrder: customOrder,
      firstDebtId: firstDebtId,
    );
    final allocation = allocateDebtPayments(
      ordered: ordered,
      balances: {for (final d in ordered) d.id: d.balanceMinor},
      month: month,
      availableMinor: availableMinor < 0 ? 0 : availableMinor,
      includeOverdue: true,
    );
    final shares = [
      for (final d in ordered)
        if (allocation.paidTo(d.id) > 0)
          PaydayShare(
            debtId: d.id,
            minimumMinor: allocation.minimumMinor[d.id] ?? 0,
            extraMinor: allocation.extraMinor[d.id] ?? 0,
          ),
    ];
    final targets = allocation.extraMinor.keys;
    return PaydaySplit._(
      shares: shares,
      targetDebtId: targets.isEmpty
          ? ordered
                .where((d) => d.balanceMinor > allocation.paidTo(d.id))
                .firstOrNull
                ?.id
          : ordered.firstWhere((d) => targets.contains(d.id)).id,
      unallocatedMinor: allocation.unallocatedMinor,
      shortfallMinor: allocation.shortfallMinor,
    );
  }

  /// Debts that get money, in payoff order.
  final List<PaydayShare> shares;

  /// The first debt that gets extra money; with no extra, the debt that
  /// would get it. Null when nothing is owed.
  final int? targetDebtId;

  /// Left over once every debt is cleared.
  final int unallocatedMinor;

  /// Scheduled payments this payday does not cover.
  final int shortfallMinor;

  int get totalMinor => shares.fold(0, (sum, s) => sum + s.totalMinor);
}
