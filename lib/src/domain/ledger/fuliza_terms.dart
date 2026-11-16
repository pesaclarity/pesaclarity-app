/// What Fuliza M-Pesa charges, and how close its messages come to the
/// payments and money in they belong to. The one place these figures live:
/// the balance walk, the journal and anything else that works out Fuliza
/// read them from here. The message reader's packs do not carry them.
class FulizaTerms {
  const FulizaTerms({
    required this.accessFeeBasisPoints,
    required this.dailyChargeBasisPoints,
    required this.minimumDailyChargeMinor,
    required this.fundedWithin,
    required this.repaidWithin,
  });

  /// The access fee on each draw, in basis points of the amount drawn.
  final int accessFeeBasisPoints;

  /// The daily charge on what is owed, in basis points a day.
  final int dailyChargeBasisPoints;

  /// The least daily charge, in minor units.
  final int minimumDailyChargeMinor;

  /// A draw this soon after a reported balance funded the payment that
  /// reported it, so that balance already holds the draw.
  final Duration fundedWithin;

  /// How far apart a repayment message and the money in it was taken from
  /// can be and still be one event.
  final Duration repaidWithin;

  /// The access fee on [drawnMinor], rounded half up as the messages do.
  int accessFee(int drawnMinor) =>
      (drawnMinor * accessFeeBasisPoints + _halfBasis) ~/ _basis;

  /// The most daily charges a repayment [days] after the debt was last known
  /// can hold on top of [owedMinor]: at least one day's.
  int chargeAllowance(int owedMinor, int days) {
    final perDay = owedMinor * dailyChargeBasisPoints ~/ _basis;
    return (days < 1 ? 1 : days) *
        (perDay < minimumDailyChargeMinor ? minimumDailyChargeMinor : perDay);
  }

  static const _basis = 10000;
  static const _halfBasis = _basis ~/ 2;
}

/// Fuliza's terms as its messages show them: a 1% access fee, 1% a day in
/// daily charges with at least 1.00 a day.
const fulizaTerms = FulizaTerms(
  accessFeeBasisPoints: 100,
  dailyChargeBasisPoints: 100,
  minimumDailyChargeMinor: 100,
  fundedWithin: Duration(minutes: 10),
  repaidWithin: Duration(minutes: 30),
);
