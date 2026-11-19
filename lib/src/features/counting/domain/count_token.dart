import 'dart:convert';
import 'dart:math';

/// The random number that lets the server count this phone once a day and
/// once a month (ADR 0024).
///
/// It is 128 random bits from [Random.secure], written as 22 base64url
/// characters, and never made from anything about the phone, the person or
/// an account. A new one is made for each calendar month (UTC).
class CountToken {
  const CountToken({required this.month, required this.value});

  /// Makes a token for the month of [now].
  factory CountToken.make(DateTime now, {Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    return CountToken(
      month: monthOf(now),
      value: base64Url.encode(bytes).replaceAll('=', ''),
    );
  }

  /// Reads a token saved by [toJson]; null when it is not one.
  static CountToken? fromJson(Object? json) {
    if (json is! Map) return null;
    final month = json['month'];
    final value = json['value'];
    if (month is! String || !_month.hasMatch(month)) return null;
    if (value is! String || !isWellFormed(value)) return null;
    return CountToken(month: month, value: value);
  }

  static final _month = RegExp(r'^\d{4}-\d{2}$');
  static final _value = RegExp(r'^[A-Za-z0-9_-]{22}$');

  /// The month a token made at [now] belongs to, such as `2026-11` (UTC).
  static String monthOf(DateTime now) {
    final utc = now.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}';
  }

  /// Whether [value] has the shape the server accepts.
  static bool isWellFormed(String value) => _value.hasMatch(value);

  /// `2026-11`.
  final String month;

  /// The 22 characters sent in the `Count-Token` header.
  final String value;

  /// Whether this token may still be sent at [now]: only in its own month.
  bool isFor(DateTime now) => month == monthOf(now);

  Map<String, Object?> toJson() => {'month': month, 'value': value};
}
