import '../time/calendar.dart';

/// Turns the text of a found field into a value. Each returns null when the
/// text does not hold one, so the person fills it in.

final _number = RegExp(r'[0-9][0-9,]*(?:\.[0-9]{1,2})?');

/// `KES 1,250.00`, `Ksh.500`, `1250.5 Kshs` → minor units.
int? amountMinorFrom(String text) {
  final match = _number.firstMatch(text);
  if (match == null) return null;
  final digits = match.group(0)!.replaceAll(',', '');
  final parts = digits.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final cents = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return whole * 100 + cents;
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

int _year(int y) => y < 100 ? 2000 + y : y;

CalendarDate? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime.utc(y, m, d);
  if (date.month != m) return null;
  return CalendarDate(y, m, d);
}

/// `29/10/26`, `29-10-2026`, `2026-10-29`, `29 Oct 2026`, `29-OCT-26`.
/// Numeric dates read day first, as Kenyan institutions write them.
CalendarDate? dateFrom(String text) {
  final iso = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (iso != null) {
    return _valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final numeric = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})')
      .firstMatch(text);
  if (numeric != null) {
    return _valid(
      _year(int.parse(numeric[3]!)),
      int.parse(numeric[2]!),
      int.parse(numeric[1]!),
    );
  }
  final words = RegExp(r'(\d{1,2})[ -]([A-Za-z]{3})[A-Za-z]*[ -](\d{2,4})')
      .firstMatch(text);
  if (words != null) {
    final month = _months.indexOf(words[2]!.toLowerCase()) + 1;
    if (month == 0) return null;
    return _valid(_year(int.parse(words[3]!)), month, int.parse(words[1]!));
  }
  return null;
}

/// `14:05`, `14:05:33`, `2:05 PM` → minutes after midnight.
int? minutesFrom(String text) {
  final m = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?')
      .firstMatch(text);
  if (m == null) return null;
  var hour = int.parse(m[1]!);
  final minute = int.parse(m[2]!);
  final half = m[3]?.toLowerCase();
  if (half != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (half == 'pm' ? 12 : 0);
  }
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// The payee as people write it: masked phone numbers and runs of spaces
/// removed, and words in capitals turned into title case.
String counterpartyFrom(String text) => text
    .replaceAll(RegExp(r'\b[0-9]{2,4}\s*\*+\s*[0-9]+\b'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .split(' ')
    .map(
      (w) => RegExp(r'^[A-Z]{2,}$').hasMatch(w)
          ? '${w[0]}${w.substring(1).toLowerCase()}'
          : w,
    )
    .join(' ');
