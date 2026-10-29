import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../time/calendar.dart';
import 'health_inputs.dart';

// Thresholds are starting points to tune with beta users. Ratios are in basis
// points of income (10,000 = 100%). Each indicator scores linearly between
// its zero-marks and full-marks thresholds.

/// Spending vs income: full marks at or under 90%, none at or over 120%.
const spendingFullBasisPoints = 9000;
const spendingZeroBasisPoints = 12000;

/// Emergency cushion: full marks at three months of essentials, none at zero.
const cushionFullMonths = 3;

/// Savings rate: full marks at 20% of income or more, none at zero.
const savingsRateFullBasisPoints = 2000;

/// Debt load: full marks at or under 20% of income, none at or over 50%.
const debtLoadFullBasisPoints = 2000;
const debtLoadZeroBasisPoints = 5000;

/// Overdraft reliance: full marks with no Fuliza days, none at eight or more
/// (about two a week).
const overdraftZeroDays = 8;

/// Leakage share: full marks at or under 10% of income, none at or over 30%.
const leakageFullBasisPoints = 1000;
const leakageZeroBasisPoints = 3000;

/// The lowest score in the Coping and Healthy bands.
const copingFromScore = 40;
const healthyFromScore = 70;

/// Each indicator is worth 12.5 points, kept in hundredths of a point so
/// scoring stays in integers.
const indicatorMaxCentipoints = 1250;

/// The Financial Health Index's four pillars, in the spec's order.
enum HealthPillar {
  spend('Spend'),
  save('Save'),
  borrow('Borrow'),
  plan('Plan');

  const HealthPillar(this.label);

  final String label;
}

/// The eight indicators, two per pillar, in the spec's order.
enum HealthIndicator {
  spendingVsIncome(HealthPillar.spend, 'Spending vs income'),
  billsOnTime(HealthPillar.spend, 'Bills on time'),
  emergencyCushion(HealthPillar.save, 'Emergency cushion'),
  savingsRate(HealthPillar.save, 'Savings rate'),
  debtLoad(HealthPillar.borrow, 'Debt load'),
  overdraftReliance(HealthPillar.borrow, 'Overdraft reliance'),
  leakageShare(HealthPillar.plan, 'Leakage share'),
  planAdherence(HealthPillar.plan, 'Plan adherence');

  const HealthIndicator(this.pillar, this.label);

  final HealthPillar pillar;
  final String label;
}

enum HealthBand {
  struggling('Struggling'),
  coping('Coping'),
  healthy('Healthy');

  const HealthBand(this.label);

  final String label;

  static HealthBand of(int score) {
    if (score >= healthyFromScore) return healthy;
    if (score >= copingFromScore) return coping;
    return struggling;
  }
}

/// One indicator's points, in hundredths of a point.
class IndicatorScore {
  const IndicatorScore(this.indicator, this.centipoints);

  final HealthIndicator indicator;
  final int centipoints;

  /// Points this indicator could still add.
  int get gapCentipoints => indicatorMaxCentipoints - centipoints;

  bool get isFull => gapCentipoints == 0;
}

/// The single change that would raise the score most: bringing [indicator]
/// to full marks.
class HealthAction {
  HealthAction({
    required this.indicator,
    required this.gainPoints,
    this.amountMinor = 0,
    this.count = 0,
    String? currency,
  }) : currency = currency ?? BaseCurrency.code;

  final HealthIndicator indicator;

  /// How much the rounded score would rise.
  final int gainPoints;

  /// The amount to cut, save or pay down a month, where the action has one.
  final int amountMinor;

  /// Bills, days or categories, where the action counts things.
  final int count;
  final String currency;

  /// The action in plain words, for example "Save KES 4,000 more a month to
  /// reach 20% of income."
  String get message {
    final amount = formatMoney(Money(amountMinor, currency: currency));
    final has = amountMinor > 0;
    return switch (indicator) {
      HealthIndicator.spendingVsIncome =>
        has
            ? 'Spend $amount less a month to keep spending under '
                  '${_percent(spendingFullBasisPoints)} of income.'
            : 'Keep spending under ${_percent(spendingFullBasisPoints)} '
                  'of income.',
      HealthIndicator.billsOnTime =>
        count == 1
            ? 'Pay your one late bill by its due date.'
            : 'Pay your $count late bills by their due dates.',
      HealthIndicator.emergencyCushion =>
        has
            ? 'Build your savings by $amount to cover '
                  '$cushionFullMonths months of essentials.'
            : 'Build your savings to cover $cushionFullMonths months of '
                  'essentials.',
      HealthIndicator.savingsRate =>
        has
            ? 'Save $amount more a month to reach '
                  '${_percent(savingsRateFullBasisPoints)} of income.'
            : 'Save ${_percent(savingsRateFullBasisPoints)} of your income '
                  'each month.',
      HealthIndicator.debtLoad =>
        has
            ? 'Bring debt payments down by $amount a month, to under '
                  '${_percent(debtLoadFullBasisPoints)} of income.'
            : 'Keep debt payments under ${_percent(debtLoadFullBasisPoints)} '
                  'of income.',
      HealthIndicator.overdraftReliance =>
        count == 1
            ? 'Go a month without Fuliza. You used it on one day.'
            : 'Go a month without Fuliza. You used it on $count days.',
      HealthIndicator.leakageShare =>
        has
            ? 'Cut leakages by $amount a month, to under '
                  '${_percent(leakageFullBasisPoints)} of income.'
            : 'Keep leakages under ${_percent(leakageFullBasisPoints)} '
                  'of income.',
      HealthIndicator.planAdherence =>
        count == 0
            ? 'Set a budget for your spending categories in Plan.'
            : count == 1
            ? 'Keep your one over-budget category within its plan.'
            : 'Keep your $count over-budget categories within their plans.',
    };
  }
}

/// The Financial Health Index for one month: a 0–100 score from eight
/// indicators of 12.5 points each.
///
/// Where income is zero, a ratio to income counts as zero when there is
/// nothing to divide (no spending, debt or leakage gets full marks) and as
/// unbounded otherwise (any spending with no income gets no marks; any saving
/// gets full marks). With no bills due, Bills on time gets full marks; with
/// no planned expense categories, Plan adherence gets none.
class HealthIndex {
  HealthIndex({
    required this.inputs,
    required this.indicators,
    required this.score,
    String? currency,
  }) : currency = currency ?? BaseCurrency.code;

  factory HealthIndex.compute(HealthInputs inputs, {String? currency}) {
    currency ??= BaseCurrency.code;
    final i = inputs;
    final scores = [
      for (final indicator in HealthIndicator.values)
        IndicatorScore(indicator, _centipoints(indicator, i)),
    ];
    final total = scores.fold(0, (s, x) => s + x.centipoints);
    return HealthIndex(
      inputs: inputs,
      indicators: List.unmodifiable(scores),
      score: _round(total),
      currency: currency,
    );
  }

  final HealthInputs inputs;

  /// One per indicator, in [HealthIndicator] order.
  final List<IndicatorScore> indicators;

  /// 0 to 100.
  final int score;
  final String currency;

  YearMonth get month => inputs.month;

  HealthBand get band => HealthBand.of(score);

  int pointsOf(HealthIndicator indicator) =>
      indicators[indicator.index].centipoints;

  /// A pillar's points in hundredths, out of 2,500.
  int pillarCentipoints(HealthPillar pillar) => indicators
      .where((s) => s.indicator.pillar == pillar)
      .fold(0, (sum, s) => sum + s.centipoints);

  /// The pillar with the fewest points; ties go to the earlier pillar.
  HealthPillar get weakestPillar {
    var weakest = HealthPillar.spend;
    for (final pillar in HealthPillar.values) {
      if (pillarCentipoints(pillar) < pillarCentipoints(weakest)) {
        weakest = pillar;
      }
    }
    return weakest;
  }

  /// The indicator with the largest gap to full marks, which is the most a
  /// single change can add. Ties go to the earlier indicator. Null at 100.
  HealthAction? get bestAction {
    IndicatorScore? best;
    for (final s in indicators) {
      if (s.gapCentipoints > (best?.gapCentipoints ?? 0)) best = s;
    }
    if (best == null) return null;
    final total = indicators.fold(0, (sum, s) => sum + s.centipoints);
    return _actionFor(
      best.indicator,
      inputs,
      gainPoints: _round(total + best.gapCentipoints) - score,
      currency: currency,
    );
  }

  /// Score change since [previous]; null without one.
  int? changeSince(HealthIndex? previous) =>
      previous == null ? null : score - previous.score;
}

int _centipoints(HealthIndicator indicator, HealthInputs i) =>
    switch (indicator) {
      HealthIndicator.spendingVsIncome => _lowerIsBetter(
        _ratio(i.spendingMinor, i.incomeMinor),
        full: spendingFullBasisPoints,
        zero: spendingZeroBasisPoints,
      ),
      HealthIndicator.billsOnTime =>
        i.billsDue <= 0
            ? indicatorMaxCentipoints
            : indicatorMaxCentipoints * i.billsPaidOnTime ~/ i.billsDue,
      HealthIndicator.emergencyCushion => _higherIsBetter(
        _ratio(i.savingsBalanceMinor, i.essentialsMinor),
        full: cushionFullMonths * 10000,
      ),
      HealthIndicator.savingsRate => _higherIsBetter(
        _ratio(i.savedMinor, i.incomeMinor),
        full: savingsRateFullBasisPoints,
      ),
      HealthIndicator.debtLoad => _lowerIsBetter(
        _ratio(i.debtPaymentsMinor, i.incomeMinor),
        full: debtLoadFullBasisPoints,
        zero: debtLoadZeroBasisPoints,
      ),
      HealthIndicator.overdraftReliance => _lowerIsBetter(
        i.overdraftDays,
        full: 0,
        zero: overdraftZeroDays,
      ),
      HealthIndicator.leakageShare => _lowerIsBetter(
        _ratio(i.leakageMinor, i.incomeMinor),
        full: leakageFullBasisPoints,
        zero: leakageZeroBasisPoints,
      ),
      HealthIndicator.planAdherence =>
        i.plannedCategories <= 0
            ? 0
            : indicatorMaxCentipoints *
                  i.categoriesWithinBudget ~/
                  i.plannedCategories,
    };

/// [part] over [whole] in basis points, or null when unbounded.
int? _ratio(int part, int whole) {
  if (whole <= 0) return part <= 0 ? 0 : null;
  return part * 10000 ~/ whole;
}

int _lowerIsBetter(int? value, {required int full, required int zero}) {
  if (value == null || value >= zero) return 0;
  if (value <= full) return indicatorMaxCentipoints;
  return indicatorMaxCentipoints * (zero - value) ~/ (zero - full);
}

int _higherIsBetter(int? value, {required int full}) {
  if (value == null || value >= full) return indicatorMaxCentipoints;
  if (value <= 0) return 0;
  return indicatorMaxCentipoints * value ~/ full;
}

int _round(int centipoints) => (centipoints + 50) ~/ 100;

int _shareOf(int income, int basisPoints) =>
    income <= 0 ? 0 : income * basisPoints ~/ 10000;

int _atLeastZero(int value) => value < 0 ? 0 : value;

String _percent(int basisPoints) => '${basisPoints ~/ 100}%';

HealthAction _actionFor(
  HealthIndicator indicator,
  HealthInputs i, {
  required int gainPoints,
  required String currency,
}) {
  var amount = 0;
  var count = 0;
  switch (indicator) {
    case HealthIndicator.spendingVsIncome:
      amount =
          i.spendingMinor - _shareOf(i.incomeMinor, spendingFullBasisPoints);
    case HealthIndicator.billsOnTime:
      count = i.billsDue - i.billsPaidOnTime;
    case HealthIndicator.emergencyCushion:
      amount = i.essentialsMinor * cushionFullMonths - i.savingsBalanceMinor;
    case HealthIndicator.savingsRate:
      final target = i.incomeMinor <= 0
          ? 0
          : (i.incomeMinor * savingsRateFullBasisPoints + 9999) ~/ 10000;
      amount = target - i.savedMinor;
    case HealthIndicator.debtLoad:
      amount =
          i.debtPaymentsMinor -
          _shareOf(i.incomeMinor, debtLoadFullBasisPoints);
    case HealthIndicator.overdraftReliance:
      count = i.overdraftDays;
    case HealthIndicator.leakageShare:
      amount = i.leakageMinor - _shareOf(i.incomeMinor, leakageFullBasisPoints);
    case HealthIndicator.planAdherence:
      count = i.plannedCategories - i.categoriesWithinBudget;
  }
  return HealthAction(
    indicator: indicator,
    gainPoints: gainPoints,
    amountMinor: _atLeastZero(amount),
    count: _atLeastZero(count),
    currency: currency,
  );
}
