import '../time/calendar.dart';
import 'debt.dart';
import 'payoff_order.dart';

/// Fifty years: a plan that has not cleared by then never will at this pace.
const defaultPayoffHorizonMonths = 600;

/// The choices behind a payoff plan.
class PayoffOptions {
  const PayoffOptions({
    required this.startMonth,
    this.strategy = PayoffStrategy.avalanche,
    this.extraMonthlyMinor = 0,
    this.customOrder = const [],
    this.firstDebtId,
    this.horizonMonths = defaultPayoffHorizonMonths,
  }) : assert(extraMonthlyMinor >= 0, 'extra is never negative'),
       assert(horizonMonths > 0, 'the horizon is at least a month');

  /// The first month with a payment.
  final YearMonth startMonth;
  final PayoffStrategy strategy;

  /// Paid each month on top of the scheduled payments.
  final int extraMonthlyMinor;

  /// Debt ids in the user's order, for [PayoffStrategy.custom].
  final List<int> customOrder;

  /// A debt to clear before all others, whatever the strategy.
  final int? firstDebtId;
  final int horizonMonths;

  PayoffOptions copyWith({
    PayoffStrategy? strategy,
    int? extraMonthlyMinor,
    List<int>? customOrder,
    int? firstDebtId,
  }) => PayoffOptions(
    startMonth: startMonth,
    strategy: strategy ?? this.strategy,
    extraMonthlyMinor: extraMonthlyMinor ?? this.extraMonthlyMinor,
    customOrder: customOrder ?? this.customOrder,
    firstDebtId: firstDebtId ?? this.firstDebtId,
    horizonMonths: horizonMonths,
  );
}

/// One debt's outcome in a plan.
class DebtPayoff {
  const DebtPayoff({
    required this.debtId,
    required this.paidOffIn,
    required this.interestMinor,
    required this.paidMinor,
    required this.remainingMinor,
  });

  final int debtId;

  /// The month the balance reaches zero; null when it never does.
  final YearMonth? paidOffIn;
  final int interestMinor;
  final int paidMinor;

  /// Still owed at the end of the horizon; zero once cleared.
  final int remainingMinor;

  bool get clears => paidOffIn != null;
}

/// One simulated month.
class PayoffMonth {
  const PayoffMonth({
    required this.month,
    required this.interestMinor,
    required this.paidMinor,
    required this.balancesMinor,
  });

  final YearMonth month;
  final int interestMinor;

  /// Paid to each debt this month, by debt id.
  final Map<int, int> paidMinor;

  /// What each debt owes at the end of the month, by debt id.
  final Map<int, int> balancesMinor;

  int get remainingMinor => balancesMinor.values.fold(0, (a, b) => a + b);
}

/// A month-by-month payoff simulation.
///
/// Each month, in order: interest is added to every formal debt with a rate,
/// one month's worth of its annual rate on the opening balance, rounded half
/// up to the minor unit; then the scheduled payments are made; then the extra
/// goes to the first debt in the payoff order that is still owed. A cleared
/// debt's scheduled payment keeps being paid and rolls on to the next target,
/// so the monthly total stays the same until everything is cleared.
///
/// Family and friend loans get no interest. Their agreed instalments are
/// their scheduled payments, and instalments due before the start month are
/// caught up in the first month.
class PayoffPlan {
  PayoffPlan._({
    required this.startMonth,
    required this.order,
    required this.debts,
    required this.months,
  });

  /// Simulates [debts] under [options]. Debts with nothing owed are left out.
  factory PayoffPlan.simulate(Iterable<Debt> debts, PayoffOptions options) {
    final open = [
      for (final d in debts)
        if (d.balanceMinor > 0) d,
    ];
    final ordered = payoffOrder(
      open,
      options.strategy,
      customOrder: options.customOrder,
      firstDebtId: options.firstDebtId,
    );
    return _run(
      ordered,
      options,
      monthlyBudget: (month, isFirst) =>
          options.extraMonthlyMinor +
          ordered.fold(
            0,
            (sum, d) =>
                sum + d.scheduledPaymentMinor(month, includeOverdue: isFirst),
          ),
      rollOver: true,
    );
  }

  /// The comparison plan: each debt gets only its scheduled payment, with no
  /// extra and nothing rolled over from cleared debts.
  factory PayoffPlan.minimumsOnly(
    Iterable<Debt> debts,
    YearMonth startMonth, {
    int horizonMonths = defaultPayoffHorizonMonths,
  }) {
    final options = PayoffOptions(
      startMonth: startMonth,
      horizonMonths: horizonMonths,
    );
    final open = [
      for (final d in debts)
        if (d.balanceMinor > 0) d,
    ];
    return _run(
      payoffOrder(open, PayoffStrategy.avalanche),
      options,
      monthlyBudget: (_, _) => 0,
      rollOver: false,
    );
  }

  static PayoffPlan _run(
    List<Debt> ordered,
    PayoffOptions options, {
    required int Function(YearMonth month, bool isFirst) monthlyBudget,
    required bool rollOver,
  }) {
    final balances = {for (final d in ordered) d.id: d.balanceMinor};
    final interest = {for (final d in ordered) d.id: 0};
    final paid = {for (final d in ordered) d.id: 0};
    final paidOffIn = <int, YearMonth>{};
    final months = <PayoffMonth>[];

    for (var i = 0; i < options.horizonMonths; i++) {
      if (paidOffIn.length == ordered.length) break;
      final month = options.startMonth.addMonths(i);
      final isFirst = i == 0;

      var monthInterest = 0;
      for (final debt in ordered) {
        final charged = debt.monthlyInterestOn(balances[debt.id]!);
        balances[debt.id] = balances[debt.id]! + charged;
        interest[debt.id] = interest[debt.id]! + charged;
        monthInterest += charged;
      }

      final Map<int, int> payments;
      if (rollOver) {
        final allocation = allocateDebtPayments(
          ordered: ordered,
          balances: balances,
          month: month,
          availableMinor: monthlyBudget(month, isFirst),
          includeOverdue: isFirst,
        );
        payments = {for (final d in ordered) d.id: allocation.paidTo(d.id)};
      } else {
        payments = {
          for (final d in ordered)
            d.id: _min(
              d.scheduledPaymentMinor(month, includeOverdue: isFirst),
              balances[d.id]!,
            ),
        };
      }

      for (final debt in ordered) {
        final payment = payments[debt.id]!;
        if (payment == 0) continue;
        balances[debt.id] = balances[debt.id]! - payment;
        paid[debt.id] = paid[debt.id]! + payment;
        if (balances[debt.id] == 0) paidOffIn.putIfAbsent(debt.id, () => month);
      }

      months.add(
        PayoffMonth(
          month: month,
          interestMinor: monthInterest,
          paidMinor: {
            for (final e in payments.entries)
              if (e.value > 0) e.key: e.value,
          },
          balancesMinor: Map.unmodifiable(balances),
        ),
      );
    }

    return PayoffPlan._(
      startMonth: options.startMonth,
      order: [for (final d in ordered) d.id],
      debts: [
        for (final d in ordered)
          DebtPayoff(
            debtId: d.id,
            paidOffIn: paidOffIn[d.id],
            interestMinor: interest[d.id]!,
            paidMinor: paid[d.id]!,
            remainingMinor: balances[d.id]!,
          ),
      ],
      months: months,
    );
  }

  final YearMonth startMonth;

  /// Debt ids in the order extra money goes to them.
  final List<int> order;

  /// One outcome per debt, in [order].
  final List<DebtPayoff> debts;
  final List<PayoffMonth> months;

  DebtPayoff debt(int id) => debts.firstWhere((d) => d.debtId == id);

  /// Debts still owed at the end of the horizon.
  List<int> get neverClears => [
    for (final d in debts)
      if (!d.clears) d.debtId,
  ];

  bool get clearsAll => neverClears.isEmpty;

  /// The month the last debt clears. Null when a debt never clears, or when
  /// nothing is owed.
  YearMonth? get debtFreeMonth {
    if (!clearsAll || debts.isEmpty) return null;
    return debts
        .map((d) => d.paidOffIn!)
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  }

  /// The debt-free date as the payday in [debtFreeMonth], with a payday past
  /// the end of a short month moved to its last day.
  CalendarDate? debtFreeOn(int paydayDay) {
    final month = debtFreeMonth;
    if (month == null) return null;
    final day = paydayDay < 1
        ? 1
        : (paydayDay > month.dayCount ? month.dayCount : paydayDay);
    return CalendarDate(month.year, month.month, day);
  }

  int get totalInterestMinor =>
      debts.fold(0, (sum, d) => sum + d.interestMinor);

  int get totalPaidMinor => debts.fold(0, (sum, d) => sum + d.paidMinor);
}

/// A plan beside another, such as a strategy against minimums only, or a
/// what-if against today's plan.
class PayoffComparison {
  const PayoffComparison({required this.plan, required this.baseline});

  /// The plan against minimums only: what the strategy and extra save.
  factory PayoffComparison.againstMinimums(
    Iterable<Debt> debts,
    PayoffOptions options,
  ) => PayoffComparison(
    plan: PayoffPlan.simulate(debts, options),
    baseline: PayoffPlan.minimumsOnly(
      debts,
      options.startMonth,
      horizonMonths: options.horizonMonths,
    ),
  );

  /// A what-if: [scenario] against [base], both on the same [debts].
  factory PayoffComparison.whatIf(
    Iterable<Debt> debts, {
    required PayoffOptions base,
    required PayoffOptions scenario,
  }) => PayoffComparison(
    plan: PayoffPlan.simulate(debts, scenario),
    baseline: PayoffPlan.simulate(debts, base),
  );

  final PayoffPlan plan;
  final PayoffPlan baseline;

  /// Interest the plan saves against the baseline; negative when it costs
  /// more. Null when either never clears, since the totals then only cover
  /// the horizon.
  int? get interestSavedMinor => plan.clearsAll && baseline.clearsAll
      ? baseline.totalInterestMinor - plan.totalInterestMinor
      : null;

  /// How many months sooner the plan is debt-free; negative when later. Null
  /// when either never clears or nothing is owed.
  int? get monthsSooner {
    final planMonth = plan.debtFreeMonth;
    final baseMonth = baseline.debtFreeMonth;
    if (planMonth == null || baseMonth == null) return null;
    return planMonth.monthsUntil(baseMonth);
  }

  /// The plan clears every debt but the baseline does not.
  bool get onlyPlanClears => plan.clearsAll && !baseline.clearsAll;
}

int _min(int a, int b) => a < b ? a : b;
