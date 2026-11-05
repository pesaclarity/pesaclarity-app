import '../ledger/activity_feed.dart';
import '../time/calendar.dart';

/// A rate as basis points: 150 is 1.5%.
typedef BasisPoints = int;

/// [amountMinor] × [rate], rounded to the nearest minor unit.
int applyRate(int amountMinor, BasisPoints rate) =>
    (amountMinor * rate / 10000).round();

/// `1.5%`, `16%`.
String rateText(BasisPoints rate) {
  final whole = rate ~/ 100;
  final part = rate % 100;
  if (part == 0) return '$whole%';
  final digits = part
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$whole.$digits%';
}

/// One income tax band: [widthMinor] of income at [rate]; the last band has
/// no width.
class TaxBand {
  const TaxBand({required this.rate, this.widthMinor});

  final int? widthMinor;
  final BasisPoints rate;
}

/// The tax rules the app estimates with: rates, thresholds and due dates,
/// each with its source. It ships inside the app, is reviewed before each
/// release, and is never fetched from a server.
class TaxPack {
  const TaxPack({
    required this.version,
    required this.rulesAsOf,
    required this.turnoverRate,
    required this.turnoverFromMinor,
    required this.turnoverUpToMinor,
    required this.turnoverDueDay,
    required this.vatRate,
    required this.vatRegisterFromMinor,
    required this.withholdingRate,
    required this.individualBands,
    required this.personalReliefMinor,
    required this.companyRate,
    required this.instalmentMonths,
    required this.instalmentDay,
    required this.instalmentsFromTaxMinor,
    required this.kraPaybills,
    required this.kraNames,
    this.sources = const {},
  });

  final int version;
  final CalendarDate rulesAsOf;

  /// Turnover Tax on gross sales, for yearly sales from
  /// [turnoverFromMinor] up to [turnoverUpToMinor].
  final BasisPoints turnoverRate;
  final int turnoverFromMinor;
  final int turnoverUpToMinor;

  /// TOT for a month is due on this day of the next month.
  final int turnoverDueDay;

  final BasisPoints vatRate;

  /// Yearly sales from which a business must register for VAT.
  final int vatRegisterFromMinor;

  /// Withholding tax on fees paid to a resident for professional or
  /// consultancy work.
  final BasisPoints withholdingRate;

  /// Yearly bands for an individual, lowest first.
  final List<TaxBand> individualBands;
  final int personalReliefMinor;
  final BasisPoints companyRate;

  /// Instalment tax months of the year and the day each is due.
  final List<int> instalmentMonths;
  final int instalmentDay;

  /// Instalments apply once the year's tax is above this.
  final int instalmentsFromTaxMinor;

  /// Paybill numbers and names that mark a payment to KRA.
  final Set<String> kraPaybills;
  final List<String> kraNames;

  /// Where each part's figures come from, by part.
  final Map<String, String> sources;

  /// Income tax for a year on [profitMinor]: the bands less personal
  /// relief for an individual, the company rate for a company.
  int incomeTax(int profitMinor, {required bool company}) {
    if (profitMinor <= 0) return 0;
    if (company) return applyRate(profitMinor, companyRate);
    var left = profitMinor;
    var tax = 0;
    for (final band in individualBands) {
      final width = band.widthMinor;
      final part = width == null || left < width ? left : width;
      tax += applyRate(part, band.rate);
      left -= part;
      if (left <= 0) break;
    }
    final due = tax - personalReliefMinor;
    return due < 0 ? 0 : due;
  }

  /// The instalment due dates of [year].
  List<CalendarDate> instalmentDates(int year) => [
    for (final m in instalmentMonths) CalendarDate(year, m, instalmentDay),
  ];

  /// The next instalment on or after [today], in its year.
  CalendarDate? nextInstalment(CalendarDate today) =>
      instalmentDates(today.year).where((d) => !d.isBefore(today)).firstOrNull;

  /// Whether a payment to [name] or paybill [paybill] went to KRA.
  bool isKra({String? name, String? paybill}) {
    if (paybill != null && kraPaybills.contains(paybill.trim())) return true;
    final n = name?.toLowerCase().trim();
    if (n == null || n.isEmpty) return false;
    return kraNames.any(
      (k) => n == k || n.startsWith('$k ') || n.contains(' $k'),
    );
  }

  static TaxPack fromJson(Map<String, Object?> json) {
    Map<String, Object?> part(String key) =>
        (json[key] as Map?)?.cast<String, Object?>() ?? const {};
    int whole(Map<String, Object?> m, String key) => (m[key]! as num).toInt();
    final tot = part('turnoverTax');
    final vat = part('vat');
    final wht = part('withholding');
    final income = part('incomeTax');
    final instalments = part('instalments');
    final kra = part('kraPayments');
    final asOf = parseCalendarDate(json['rulesAsOf'] as String?);
    if (asOf == null) throw const FormatException('Tax pack has no date');
    return TaxPack(
      version: (json['version']! as num).toInt(),
      rulesAsOf: asOf,
      turnoverRate: whole(tot, 'rateBasisPoints'),
      turnoverFromMinor: whole(tot, 'fromMinor'),
      turnoverUpToMinor: whole(tot, 'upToMinor'),
      turnoverDueDay: whole(tot, 'dueDay'),
      vatRate: whole(vat, 'rateBasisPoints'),
      vatRegisterFromMinor: whole(vat, 'registerFromMinor'),
      withholdingRate: whole(wht, 'residentFeesBasisPoints'),
      individualBands: [
        for (final b
            in (income['individualBands']! as List)
                .cast<Map<String, Object?>>())
          TaxBand(
            widthMinor: (b['widthMinor'] as num?)?.toInt(),
            rate: (b['rateBasisPoints']! as num).toInt(),
          ),
      ],
      personalReliefMinor: whole(income, 'personalReliefMinor'),
      companyRate: whole(income, 'companyRateBasisPoints'),
      instalmentMonths: [
        for (final m in instalments['months']! as List) (m as num).toInt(),
      ],
      instalmentDay: whole(instalments, 'day'),
      instalmentsFromTaxMinor: whole(instalments, 'fromTaxMinor'),
      kraPaybills: {
        for (final p in (kra['paybills'] as List?) ?? const []) '$p',
      },
      kraNames: [
        for (final n in (kra['names'] as List?) ?? const []) '$n'.toLowerCase(),
      ],
      sources: {
        for (final key in [
          'turnoverTax',
          'vat',
          'withholding',
          'incomeTax',
          'instalments',
        ])
          if (part(key)['source'] case final String s) key: s,
      },
    );
  }
}
