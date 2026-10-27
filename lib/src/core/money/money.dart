import 'currency_data.dart';

/// The currency the person counts in, which totals, budgets and new amounts
/// use when no other is given.
///
/// Like `Intl.defaultLocale`, it is one setting for the whole running app:
/// the base currency provider sets it whenever the person's choice is read
/// or changed, before anything is converted into it. KES until then.
abstract final class BaseCurrency {
  static String code = 'KES';
}

/// An amount of money in integer minor units (cents), never a double. In
/// the [BaseCurrency] unless another [currency] is given.
class Money {
  Money(this.minorUnits, {String? currency})
    : currency = currency ?? BaseCurrency.code;

  /// Builds a [Money] from whole major units, for example `Money.major(1200)`.
  Money.major(int majorUnits, {String? currency})
    : currency = currency ?? BaseCurrency.code,
      minorUnits =
          majorUnits * _pow10(minorUnitDigits(currency ?? BaseCurrency.code));

  final int minorUnits;

  /// ISO 4217 currency code.
  final String currency;

  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency: currency);
  }

  Money operator -() => Money(-minorUnits, currency: currency);

  void _checkSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Cannot combine $currency with ${other.currency} without a rate',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => 'Money($minorUnits, $currency)';
}

/// Number of minor-unit digits for [currency], from the currency catalogue;
/// 2 for a code it does not list.
int minorUnitDigits(String currency) =>
    currencyCatalogue[currency]?.digits ?? 2;

/// [minor] units of a currency with [fromDigits] minor digits, in units of
/// one with [toDigits], rounded half away from zero.
int rescaleMinor(int minor, {required int fromDigits, required int toDigits}) {
  if (fromDigits == toDigits) return minor;
  if (toDigits > fromDigits) return minor * _pow10(toDigits - fromDigits);
  final divisor = _pow10(fromDigits - toDigits);
  final half = divisor ~/ 2;
  return minor >= 0 ? (minor + half) ~/ divisor : -((-minor + half) ~/ divisor);
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
