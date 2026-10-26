import '../enums.dart';
import '../payees/payee_identifier.dart';
import '../time/calendar.dart';

/// Basis points in a whole, times twelve months: the divisor that turns an
/// annual rate in basis points into one month's interest.
const _monthlyRateDivisor = 10000 * 12;

/// One debt as the payoff rules see it: what is owed now, in integer minor
/// units, with its rate and the payment the lender or family expects.
class Debt {
  const Debt({
    required this.id,
    required this.lender,
    required this.type,
    required this.balanceMinor,
    this.currency = 'KES',
    this.annualRateBasisPoints = 0,
    this.minimumPaymentMinor = 0,
    bool? isFormal,
    this.instalments = const [],
    this.payeeId,
    this.identifiers = const [],
  }) : isFormal = isFormal ?? type != DebtType.family,
       assert(balanceMinor >= 0, 'balanceMinor is never negative'),
       assert(annualRateBasisPoints >= 0, 'rates are never negative'),
       assert(minimumPaymentMinor >= 0, 'minimums are never negative');

  final int id;
  final String lender;
  final DebtType type;

  /// What is owed now.
  final int balanceMinor;
  final String currency;

  /// Annual interest rate in basis points (1,250 = 12.5%).
  final int annualRateBasisPoints;

  /// The monthly payment the lender expects. For a family loan with
  /// [instalments], the instalments are used instead.
  final int minimumPaymentMinor;

  /// Agreed instalments still to pay on a family or friend loan, oldest
  /// first. Empty for formal debts and for family loans with no plan.
  final List<DebtInstalment> instalments;

  /// The payee repayments go to, for spotting repayments in the ledger.
  final int? payeeId;

  /// Raw identifiers repayments go to, such as the lender's paybill.
  final List<PayeeIdentifier> identifiers;

  /// False for family and friend loans. Defaults from [type].
  final bool isFormal;

  /// Family and friend loans never get interest maths, whatever rate is set.
  bool get chargesInterest => isFormal && annualRateBasisPoints > 0;

  /// One month's interest on [balance], rounded half up to the minor unit.
  int monthlyInterestOn(int balance) {
    if (!chargesInterest || balance <= 0) return 0;
    return (balance * annualRateBasisPoints + _monthlyRateDivisor ~/ 2) ~/
        _monthlyRateDivisor;
  }

  /// What is due in [month] before any extra.
  ///
  /// With [instalments], the instalments due in [month]; when
  /// [includeOverdue] is set, also those due earlier, so a missed instalment
  /// is caught up. Otherwise [minimumPaymentMinor]. Not capped at the balance.
  int scheduledPaymentMinor(YearMonth month, {bool includeOverdue = false}) {
    if (instalments.isEmpty) return minimumPaymentMinor;
    var due = 0;
    for (final instalment in instalments) {
      final dueMonth = instalment.dueDate.yearMonth;
      if (dueMonth == month || (includeOverdue && dueMonth < month)) {
        due += instalment.amountMinor;
      }
    }
    return due;
  }

  Debt withBalance(int balanceMinor) => Debt(
    id: id,
    lender: lender,
    type: type,
    balanceMinor: balanceMinor,
    currency: currency,
    annualRateBasisPoints: annualRateBasisPoints,
    minimumPaymentMinor: minimumPaymentMinor,
    isFormal: isFormal,
    instalments: instalments,
    payeeId: payeeId,
    identifiers: identifiers,
  );

  @override
  String toString() => 'Debt($id, ${type.name} $lender $balanceMinor)';
}

/// One agreed instalment on a family or friend loan.
class DebtInstalment {
  const DebtInstalment({required this.dueDate, required this.amountMinor})
    : assert(amountMinor > 0, 'instalments are positive');

  final CalendarDate dueDate;
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is DebtInstalment &&
      other.dueDate == dueDate &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(dueDate, amountMinor);

  @override
  String toString() => 'DebtInstalment($dueDate, $amountMinor)';
}

extension on YearMonth {
  bool operator <(YearMonth other) => compareTo(other) < 0;
}
