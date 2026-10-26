import '../time/calendar.dart';
import 'debt.dart';

/// How money beyond the minimums is aimed.
enum PayoffStrategy {
  /// Highest rate first; ties go to the smaller balance.
  avalanche,

  /// Smallest balance first; ties go to the higher rate.
  snowball,

  /// The user's own order; debts left out follow in avalanche order.
  custom,
}

/// [debts] in the order extra money goes to them.
///
/// [firstDebtId], when given, goes first whatever the strategy: the
/// "clear this one first" what-if. The order is fixed once, from today's
/// balances, so a plan does not reshuffle as balances move. Remaining ties
/// fall back to the debt id, so the order is always the same.
List<Debt> payoffOrder(
  Iterable<Debt> debts,
  PayoffStrategy strategy, {
  List<int> customOrder = const [],
  int? firstDebtId,
}) {
  int avalanche(Debt a, Debt b) {
    final byRate = _rate(b).compareTo(_rate(a));
    if (byRate != 0) return byRate;
    final byBalance = a.balanceMinor.compareTo(b.balanceMinor);
    if (byBalance != 0) return byBalance;
    return a.id.compareTo(b.id);
  }

  int snowball(Debt a, Debt b) {
    final byBalance = a.balanceMinor.compareTo(b.balanceMinor);
    if (byBalance != 0) return byBalance;
    final byRate = _rate(b).compareTo(_rate(a));
    if (byRate != 0) return byRate;
    return a.id.compareTo(b.id);
  }

  int custom(Debt a, Debt b) {
    final ia = customOrder.indexOf(a.id);
    final ib = customOrder.indexOf(b.id);
    if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    return avalanche(a, b);
  }

  final compare = switch (strategy) {
    PayoffStrategy.avalanche => avalanche,
    PayoffStrategy.snowball => snowball,
    PayoffStrategy.custom => custom,
  };
  return debts.toList()..sort((a, b) {
    if (a.id == firstDebtId && b.id != firstDebtId) return -1;
    if (b.id == firstDebtId && a.id != firstDebtId) return 1;
    return compare(a, b);
  });
}

/// The rate that counts when ordering: zero for loans without interest maths.
int _rate(Debt debt) => debt.chargesInterest ? debt.annualRateBasisPoints : 0;

/// How one month's (or one payday's) money is spread over the debts.
class DebtAllocation {
  const DebtAllocation({
    required this.minimumMinor,
    required this.extraMinor,
    required this.unallocatedMinor,
    required this.shortfallMinor,
  });

  /// Paid towards each debt's scheduled payment, by debt id.
  final Map<int, int> minimumMinor;

  /// Paid on top of the scheduled payment, by debt id.
  final Map<int, int> extraMinor;

  /// Money left once every debt is cleared.
  final int unallocatedMinor;

  /// Scheduled payments the money did not cover.
  final int shortfallMinor;

  int paidTo(int debtId) =>
      (minimumMinor[debtId] ?? 0) + (extraMinor[debtId] ?? 0);
}

/// Spreads [availableMinor] over [ordered] debts: scheduled payments first,
/// each capped at what is owed, then the rest to the first debt in the order
/// that is still owed, and on down the order as each one clears.
///
/// [balances] gives what is owed by debt id. When the money does not cover
/// every scheduled payment, they are met in [ordered] order and the gap is
/// the shortfall.
DebtAllocation allocateDebtPayments({
  required List<Debt> ordered,
  required Map<int, int> balances,
  required YearMonth month,
  required int availableMinor,
  bool includeOverdue = false,
}) {
  final minimum = <int, int>{};
  final extra = <int, int>{};
  final owed = Map.of(balances);
  var left = availableMinor;
  var shortfall = 0;

  for (final debt in ordered) {
    final balance = owed[debt.id] ?? 0;
    if (balance <= 0) continue;
    final scheduled = _min(
      debt.scheduledPaymentMinor(month, includeOverdue: includeOverdue),
      balance,
    );
    final paid = _min(scheduled, left);
    shortfall += scheduled - paid;
    left -= paid;
    if (paid > 0) minimum[debt.id] = paid;
    owed[debt.id] = balance - paid;
  }

  for (final debt in ordered) {
    if (left <= 0) break;
    final balance = owed[debt.id] ?? 0;
    if (balance <= 0) continue;
    final paid = _min(balance, left);
    left -= paid;
    extra[debt.id] = paid;
    owed[debt.id] = balance - paid;
  }

  return DebtAllocation(
    minimumMinor: minimum,
    extraMinor: extra,
    unallocatedMinor: left,
    shortfallMinor: shortfall,
  );
}

int _min(int a, int b) => a < b ? a : b;
