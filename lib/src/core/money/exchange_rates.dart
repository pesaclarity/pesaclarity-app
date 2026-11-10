import '../../domain/time/calendar.dart';
import 'currency_data.dart';
import 'money.dart';

/// Exchange rates as a rates service publishes them: one [base] unit buys
/// `rates[code]` of each other currency.
class ExchangeRates {
  const ExchangeRates({
    required this.base,
    required this.rates,
    required this.fetchedAt,
  });

  /// Reads a rates service's JSON: a `rates` (or `conversion_rates`) object
  /// of currency codes to positive numbers, and the base under `base_code`
  /// or `base`. Null when it is not that shape.
  static ExchangeRates? fromJson(Object? json, {required DateTime fetchedAt}) {
    if (json is! Map) return null;
    final base = json['base_code'] ?? json['base'];
    final raw = json['rates'] ?? json['conversion_rates'];
    if (base is! String || raw is! Map) return null;
    final rates = <String, double>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is String && value is num && value > 0) {
        rates[key.toUpperCase()] = value.toDouble();
      }
    }
    if (rates.isEmpty) return null;
    return ExchangeRates(
      base: base.toUpperCase(),
      rates: {...rates, base.toUpperCase(): 1},
      fetchedAt: fetchedAt.toUtc(),
    );
  }

  /// As saved by [toJson].
  static ExchangeRates? fromSaved(Map<String, Object?> json) {
    final at = DateTime.tryParse('${json['fetchedAt']}');
    return at == null ? null : fromJson(json, fetchedAt: at);
  }

  final String base;
  final Map<String, double> rates;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() => {
    'base': base,
    'rates': rates,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  /// How much of [code] one unit of [from] buys, or null when either is
  /// missing.
  double? rate(String from, String code) {
    final a = rates[from];
    final b = rates[code];
    return a == null || b == null ? null : b / a;
  }
}

/// One day's rates, kept so that amounts from that day convert at them.
class DayRates {
  const DayRates(this.day, this.rates);

  final CalendarDate day;
  final ExchangeRates rates;
}

/// The rates kept day by day, oldest first.
class RateHistory {
  RateHistory(Iterable<DayRates> days)
    : days = List.unmodifiable(
        <DayRates>[...days]
          ..sort((DayRates a, DayRates b) => a.day.compareTo(b.day)),
      );

  static final empty = RateHistory(const []);

  final List<DayRates> days;

  bool get isEmpty => days.isEmpty;

  /// The rates for [day]: its own, else the closest earlier day's, else the
  /// oldest kept, which come from after it. Null when none are kept.
  DayRates? on(CalendarDate day) {
    if (days.isEmpty) return null;
    var low = 0;
    var high = days.length - 1;
    DayRates? found;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (days[mid].day.isAfter(day)) {
        high = mid - 1;
      } else {
        found = days[mid];
        low = mid + 1;
      }
    }
    return found ?? days.first;
  }
}

/// Where the rate for an amount came from.
enum RateKind {
  /// The person's own rate for the currency.
  own,

  /// The rate the person got for this payment.
  got,

  /// The rates kept on the payment's day.
  sameDay,

  /// The rates of the closest earlier day.
  earlierDay,

  /// The oldest rates kept, from after the payment's day: approximate.
  approximate,

  /// The latest rates, when none are kept by day.
  latest,
}

/// An amount converted into the base currency: [baseMinor], at a rate where
/// one base unit buys [baseBuys] of the amount's currency, chosen as [kind]
/// from [day]'s rates (null for the person's own rates).
class Converted {
  const Converted({
    required this.baseMinor,
    required this.baseBuys,
    required this.kind,
    this.day,
  });

  final int baseMinor;
  final double baseBuys;
  final RateKind kind;
  final CalendarDate? day;
}

/// [minor] units of [from] in minor units of [to], when one [from] buys
/// [rate] of [to].
int convertMinor(
  int minor, {
  required String from,
  required String to,
  required double rate,
}) {
  final value =
      minor *
      rate *
      CurrencyConverter._pow10(minorUnitDigits(to)) /
      CurrencyConverter._pow10(minorUnitDigits(from));
  return value.round();
}

/// Converts amounts into the [base] currency, with the person's own rates
/// ([ownRates]: one base unit buys that much of a currency) taking
/// precedence over [rates]. With a [history], an amount converts at the
/// rates of its day.
class CurrencyConverter {
  const CurrencyConverter({
    required this.base,
    this.rates,
    this.ownRates = const {},
    this.history,
  });

  final String base;
  final ExchangeRates? rates;
  final Map<String, double> ownRates;
  final RateHistory? history;

  /// How much of [code] one [base] unit buys, or null when unknown.
  double? rateFor(String code) {
    if (code == base) return 1;
    return ownRates[code] ?? rates?.rate(base, code);
  }

  /// How much of [code] one [base] unit bought at [when], and where that
  /// rate came from: the person's own rate, else the rates kept for that
  /// day ([history]), else the latest. Null when there is none.
  ({double rate, RateKind kind, CalendarDate? day})? rateOn(
    String code,
    DateTime when,
  ) {
    if (code == base) return (rate: 1, kind: RateKind.sameDay, day: null);
    final own = ownRates[code];
    if (own != null) return (rate: own, kind: RateKind.own, day: null);
    final day = CalendarDate.local(when);
    final kept = history?.on(day);
    final keptRate = kept?.rates.rate(base, code);
    if (kept != null && keptRate != null) {
      return (
        rate: keptRate,
        kind: kept.day == day
            ? RateKind.sameDay
            : kept.day.isBefore(day)
            ? RateKind.earlierDay
            : RateKind.approximate,
        day: kept.day,
      );
    }
    final latest = rates;
    final latestRate = latest?.rate(base, code);
    if (latest == null || latestRate == null) return null;
    return (
      rate: latestRate,
      kind: RateKind.latest,
      day: CalendarDate.local(latest.fetchedAt),
    );
  }

  /// [minor] units of [from], paid at [when], in the base currency. With
  /// [gotCurrency] and [gotRate] (one [gotCurrency] bought [gotRate] of
  /// [from], as the person got it), that rate is used, and [when]'s rate
  /// only to go on from [gotCurrency] to the base. Null with no rate.
  Converted? convert(
    int minor,
    String from,
    DateTime when, {
    String? gotCurrency,
    double? gotRate,
  }) {
    if (gotCurrency != null && gotRate != null && gotRate > 0) {
      final inGot = convertMinor(
        minor,
        from: from,
        to: gotCurrency,
        rate: 1 / gotRate,
      );
      final step = rateOn(gotCurrency, when);
      if (step == null) return null;
      return Converted(
        baseMinor: gotCurrency == base
            ? inGot
            : convertMinor(
                inGot,
                from: gotCurrency,
                to: base,
                rate: 1 / step.rate,
              ),
        baseBuys: step.rate * gotRate,
        kind: RateKind.got,
        day: CalendarDate.local(when),
      );
    }
    final rate = rateOn(from, when);
    if (rate == null) return null;
    return Converted(
      baseMinor: convertMinor(minor, from: from, to: base, rate: 1 / rate.rate),
      baseBuys: rate.rate,
      kind: rate.kind,
      day: rate.day,
    );
  }

  /// [minor] units of [from] in base minor units, or null with no rate.
  int? toBase(int minor, String from) {
    if (from == base) return minor;
    final rate = rateFor(from);
    if (rate == null) return null;
    final fromDigits = minorUnitDigits(from);
    final baseDigits = minorUnitDigits(base);
    final value = minor / rate * _pow10(baseDigits) / _pow10(fromDigits);
    return value.round();
  }

  /// [minor] base units in [to] minor units, or null with no rate.
  int? fromBase(int minor, String to) {
    if (to == base) return minor;
    final rate = rateFor(to);
    if (rate == null) return null;
    final value =
        minor *
        rate *
        _pow10(minorUnitDigits(to)) /
        _pow10(minorUnitDigits(base));
    return value.round();
  }

  static double _pow10(int n) {
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}

/// The currency of the phone's [region] (an ISO 3166 code such as `KE`), or
/// null when it is not known.
String? currencyOfRegion(String? region) =>
    region == null ? null : territoryCurrencies[region.toUpperCase()];

/// Whether [code] is a currency the app knows.
bool isKnownCurrency(String code) => currencyCatalogue.containsKey(code);

/// The base currency to use when the person has not chosen one: their
/// region's, else [BaseCurrency.code].
String suggestedCurrency(String? region) =>
    currencyOfRegion(region) ?? BaseCurrency.code;
