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

/// Converts amounts into the [base] currency, with the person's own rates
/// ([ownRates]: one base unit buys that much of a currency) taking
/// precedence over [rates].
class CurrencyConverter {
  const CurrencyConverter({
    required this.base,
    this.rates,
    this.ownRates = const {},
  });

  final String base;
  final ExchangeRates? rates;
  final Map<String, double> ownRates;

  /// How much of [code] one [base] unit buys, or null when unknown.
  double? rateFor(String code) {
    if (code == base) return 1;
    return ownRates[code] ?? rates?.rate(base, code);
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
