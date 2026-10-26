import 'money.dart';

/// Formats [money] the way the app shows amounts, for example `KES 1,200`.
///
/// Minor units are shown only when they are not zero (`KES 1,200.50`), unless
/// [alwaysShowMinorUnits] is set. With [withCurrency] false the code is left
/// out (`1,200`), for places where the currency is already clear.
String formatMoney(
  Money money, {
  bool withCurrency = true,
  bool alwaysShowMinorUnits = false,
}) {
  final digits = minorUnitDigits(money.currency);
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }

  final absolute = money.minorUnits.abs();
  final major = absolute ~/ divisor;
  final minor = absolute % divisor;

  final buffer = StringBuffer();
  if (money.isNegative) buffer.write('-');
  if (withCurrency) buffer.write('${money.currency} ');
  buffer.write(_groupThousands(major));
  if (digits > 0 && (minor != 0 || alwaysShowMinorUnits)) {
    buffer.write('.${minor.toString().padLeft(digits, '0')}');
  }
  return buffer.toString();
}

String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
