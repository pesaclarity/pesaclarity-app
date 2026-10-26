/// Turns what someone typed into a Kenyan mobile number in E.164 form
/// (+2547XXXXXXXX or +2541XXXXXXXX), or null when it is not one.
///
/// Accepts `0712 345 678`, `712345678`, `254712345678` and `+254 712 345 678`.
String? normaliseKenyanMobile(String input) {
  final digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (!RegExp(r'^\+?\d+$').hasMatch(digits)) return null;
  var national = digits.startsWith('+') ? digits.substring(1) : digits;
  if (national.startsWith('254') && national.length == 12) {
    national = national.substring(3);
  } else if (national.startsWith('0') && national.length == 10) {
    national = national.substring(1);
  }
  if (!RegExp(r'^[17]\d{8}$').hasMatch(national)) return null;
  return '+254$national';
}

/// Formats an E.164 Kenyan number for display, such as `+254 712 345 678`.
String formatKenyanMobile(String e164) {
  final match = RegExp(r'^\+254(\d{3})(\d{3})(\d{3})$').firstMatch(e164);
  if (match == null) return e164;
  return '+254 ${match[1]} ${match[2]} ${match[3]}';
}
