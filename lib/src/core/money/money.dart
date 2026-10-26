/// An amount of money in integer minor units (cents for KES), never a double.
class Money {
  const Money(this.minorUnits, {this.currency = 'KES'});

  /// Builds a [Money] from whole major units, for example `Money.major(1200)`.
  Money.major(int majorUnits, {this.currency = 'KES'})
    : minorUnits = majorUnits * _pow10(minorUnitDigits(currency));

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

/// Number of minor-unit digits for [currency]; 2 unless listed otherwise.
int minorUnitDigits(String currency) => switch (currency) {
  'UGX' || 'RWF' || 'BIF' || 'JPY' => 0,
  _ => 2,
};

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
