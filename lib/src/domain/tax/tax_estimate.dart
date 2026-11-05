import '../time/calendar.dart';
import 'tax_pack.dart';

/// How the business files, set in Tax settings.
class TaxSettings {
  const TaxSettings({
    this.company = false,
    this.vatRegistered = false,
    this.setAside,
  });

  /// Files as a company (the company rate), else as an individual.
  final bool company;
  final bool vatRegistered;

  /// The share of money in kept aside for tax; null when off.
  final BasisPoints? setAside;

  TaxSettings copyWith({
    bool? company,
    bool? vatRegistered,
    BasisPoints? Function()? setAside,
  }) => TaxSettings(
    company: company ?? this.company,
    vatRegistered: vatRegistered ?? this.vatRegistered,
    setAside: setAside == null ? this.setAside : setAside(),
  );

  Map<String, Object?> toJson() => {
    'company': company,
    'vatRegistered': vatRegistered,
    'setAside': ?setAside,
  };

  static TaxSettings fromJson(Map<String, Object?>? json) {
    final aside = json?['setAside'];
    return TaxSettings(
      company: json?['company'] == true,
      vatRegistered: json?['vatRegistered'] == true,
      setAside: aside is num && aside > 0 && aside < 10000
          ? aside.toInt()
          : null,
    );
  }
}

/// One month's tax: what the records say it comes to, and what was paid.
class MonthTax {
  const MonthTax({
    required this.month,
    required this.estimatedMinor,
    this.paidMinor,
  });

  final YearMonth month;
  final int estimatedMinor;

  /// Paid to KRA for it; null while it is not due yet.
  final int? paidMinor;
}

/// The share to keep aside: the Turnover Tax rate, or what income tax
/// comes to as a share of money in, rounded up to a whole percent.
BasisPoints suggestedSetAside({
  required TaxKind kind,
  required TaxPack pack,
  required int taxMinor,
  required int incomeMinor,
}) {
  if (kind == TaxKind.turnover) return pack.turnoverRate;
  if (incomeMinor <= 0 || taxMinor <= 0) return 500;
  final share = taxMinor * 10000 / incomeMinor;
  final whole = (share / 100).ceil() * 100;
  return whole.clamp(100, 5000);
}

/// Which tax a business's estimate uses.
enum TaxKind {
  /// Sales over the last 12 months are below the Turnover Tax band.
  belowTurnover,

  /// Turnover Tax on gross sales.
  turnover,

  /// Income tax on profit: services, and sales above the TOT band.
  incomeTax,
}

/// The tax kind for a business that sells products when it has
/// [yearSalesMinor] of sales over the last 12 months, or one paid for its
/// services (Turnover Tax does not cover professional fees).
TaxKind taxKindFor({
  required TaxPack pack,
  required int yearSalesMinor,
  required bool services,
}) {
  if (services) return TaxKind.incomeTax;
  if (yearSalesMinor < pack.turnoverFromMinor) return TaxKind.belowTurnover;
  if (yearSalesMinor > pack.turnoverUpToMinor) return TaxKind.incomeTax;
  return TaxKind.turnover;
}

/// Money in, costs and tax already paid for a period, as the tax estimate
/// needs them: tax paid is not a cost.
class TaxFigures {
  const TaxFigures({
    required this.incomeMinor,
    required this.costsMinor,
    required this.paidToKraMinor,
    required this.withheldMinor,
    this.costNames = const [],
  });

  final int incomeMinor;
  final int costsMinor;

  /// Paid to KRA from the business's accounts.
  final int paidToKraMinor;

  /// Kept back by clients and paid to KRA for the business.
  final int withheldMinor;

  /// The largest costs, largest first.
  final List<String> costNames;

  int get profitMinor => incomeMinor - costsMinor;
}

/// Turnover Tax for one month: due on the pack's day of the next month.
class TurnoverMonth {
  const TurnoverMonth({
    required this.month,
    required this.salesMinor,
    required this.taxMinor,
    required this.paidMinor,
    required this.due,
  });

  final YearMonth month;
  final int salesMinor;
  final int taxMinor;

  /// Paid to KRA from the 1st of the next month, when TOT for the month is
  /// paid.
  final int paidMinor;
  final CalendarDate due;

  int get leftMinor => taxMinor - paidMinor < 0 ? 0 : taxMinor - paidMinor;
}

TurnoverMonth turnoverMonth(
  TaxPack pack, {
  required YearMonth month,
  required int salesMinor,
  required int paidMinor,
}) => TurnoverMonth(
  month: month,
  salesMinor: salesMinor,
  taxMinor: applyRate(salesMinor, pack.turnoverRate),
  paidMinor: paidMinor,
  due: CalendarDate(month.next.year, month.next.month, pack.turnoverDueDay),
);

/// Income tax for the year so far: on profit to date, less what clients
/// withheld and what was paid to KRA.
class IncomeTaxEstimate {
  const IncomeTaxEstimate({
    required this.year,
    required this.figures,
    required this.taxMinor,
    required this.company,
    this.nextInstalment,
  });

  final int year;
  final TaxFigures figures;
  final int taxMinor;
  final bool company;
  final CalendarDate? nextInstalment;

  int get leftMinor {
    final left = taxMinor - figures.withheldMinor - figures.paidToKraMinor;
    return left < 0 ? 0 : left;
  }
}

IncomeTaxEstimate incomeTaxEstimate(
  TaxPack pack, {
  required TaxFigures figures,
  required TaxSettings settings,
  required CalendarDate today,
}) {
  final tax = pack.incomeTax(figures.profitMinor, company: settings.company);
  return IncomeTaxEstimate(
    year: today.year,
    figures: figures,
    taxMinor: tax,
    company: settings.company,
    nextInstalment: tax > pack.instalmentsFromTaxMinor
        ? pack.nextInstalment(today)
        : null,
  );
}

/// A line the business is close to crossing, as a plain sentence, or null.
/// [near] is the share of a line, in basis points, from which it warns.
String? thresholdWarning(
  TaxPack pack, {
  required int yearSalesMinor,
  required TaxSettings settings,
  required String Function(int minor) plain,
  BasisPoints near = 8000,
}) {
  bool close(int line) =>
      yearSalesMinor >= applyRate(line, near) && yearSalesMinor < line;
  if (!settings.vatRegistered && close(pack.vatRegisterFromMinor)) {
    return 'Sales over the last 12 months are ${plain(yearSalesMinor)}. '
        'From ${plain(pack.vatRegisterFromMinor)} a year, the business '
        'registers for VAT.';
  }
  if (!settings.vatRegistered && yearSalesMinor >= pack.vatRegisterFromMinor) {
    return 'Sales over the last 12 months are ${plain(yearSalesMinor)}, '
        'past the VAT line of ${plain(pack.vatRegisterFromMinor)}. If you '
        'have registered, turn on VAT registered below.';
  }
  if (close(pack.turnoverUpToMinor)) {
    return 'Sales are near the top of the Turnover Tax band '
        '(${plain(pack.turnoverUpToMinor)} a year). Above it, income tax on '
        'profit applies.';
  }
  return null;
}
