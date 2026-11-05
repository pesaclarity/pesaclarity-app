/// A country's calling code, for numbers typed without one.
class CallingCode {
  const CallingCode(this.region, this.code, this.country);

  /// ISO region, such as KE.
  final String region;

  /// Digits after the plus, such as 254.
  final String code;
  final String country;
}

/// Calling codes offered by the picker, East Africa first.
const callingCodes = [
  CallingCode('KE', '254', 'Kenya'),
  CallingCode('TZ', '255', 'Tanzania'),
  CallingCode('UG', '256', 'Uganda'),
  CallingCode('RW', '250', 'Rwanda'),
  CallingCode('BI', '257', 'Burundi'),
  CallingCode('SS', '211', 'South Sudan'),
  CallingCode('ET', '251', 'Ethiopia'),
  CallingCode('SO', '252', 'Somalia'),
  CallingCode('CD', '243', 'DR Congo'),
  CallingCode('NG', '234', 'Nigeria'),
  CallingCode('GH', '233', 'Ghana'),
  CallingCode('ZA', '27', 'South Africa'),
  CallingCode('AE', '971', 'United Arab Emirates'),
  CallingCode('IN', '91', 'India'),
  CallingCode('GB', '44', 'United Kingdom'),
  CallingCode('US', '1', 'United States and Canada'),
];

/// The calling code for [region], Kenya's when it is not known.
CallingCode callingCodeFor(String? region) =>
    callingCodes.where((c) => c.region == region?.toUpperCase()).firstOrNull ??
    callingCodes.first;

/// [number] in full international form, `+254712345678`: as given when it
/// starts with + or 00, else with [code] in place of a leading 0. Null when
/// it has too few digits to be a phone number.
String? internationalNumber(String number, CallingCode code) {
  final trimmed = number.trim();
  var digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (trimmed.startsWith('+')) {
    // Already international.
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else {
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!digits.startsWith(code.code) || digits.length <= 9) {
      digits = '${code.code}$digits';
    }
  }
  return digits.length < 8 ? null : '+$digits';
}

/// The WhatsApp link for [international] with [text] filled in.
Uri whatsAppLink(String international, String text) => Uri.parse(
  'https://wa.me/${international.replaceAll('+', '')}'
  '?text=${Uri.encodeComponent(text)}',
);

/// The SMS link for [international] with [text] filled in. iPhones read
/// the body after `&`.
Uri smsLink(
  String international,
  String text, {
  bool iPhone = false,
}) => Uri.parse(
  'sms:$international${iPhone ? '&' : '?'}body=${Uri.encodeComponent(text)}',
);
