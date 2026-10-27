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

/// Reads an amount typed by the person, such as `1,200` or `1200.50`, as
/// minor units. Null when it is not a positive amount with at most the
/// currency's minor digits.
int? parseMoneyMinor(String input, {String? currency}) {
  final digits = minorUnitDigits(currency ?? BaseCurrency.code);
  final clean = input.replaceAll(RegExp(r'[\s,]'), '');
  final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(clean);
  if (match == null) return null;
  final fraction = match.group(2) ?? '';
  if (fraction.length > digits) return null;
  final major = int.tryParse(match.group(1)!);
  if (major == null) return null;
  var minor = major;
  for (var i = 0; i < digits; i++) {
    minor *= 10;
  }
  final value =
      minor +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(digits, '0')));
  return value > 0 ? value : null;
}
