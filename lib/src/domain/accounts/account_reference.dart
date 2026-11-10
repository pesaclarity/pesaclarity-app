/// An account number as a message prints it, usually masked with a few
/// digits at each end: `0170*****4321` shows `0170` and `4321`.
class AccountReference {
  AccountReference._(this.start, this.end, {required this.masked});

  /// Reads [printed]; null when it shows no digits.
  static AccountReference? tryParse(String? printed) {
    if (printed == null) return null;
    final text = printed.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'\d').hasMatch(text)) return null;
    if (RegExp(r'^\d+$').hasMatch(text)) {
      return AccountReference._(text, text, masked: false);
    }
    final start = RegExp(r'^\d*').firstMatch(text)!.group(0)!;
    final end = RegExp(r'\d*$').firstMatch(text)!.group(0)!;
    return AccountReference._(start, end, masked: true);
  }

  /// The digits shown before the mask, and after it. For a number printed
  /// in full, both are the whole number.
  final String start;
  final String end;
  final bool masked;

  int get _shown => masked ? start.length + end.length : start.length;

  /// Whether [other] shows more of the number than this one.
  bool showsLessThan(AccountReference other) => _shown < other._shown;

  /// Whether this and [other] can be the same account: the digits both
  /// show agree, and they share at least one end. `***4321` and
  /// `0170*****4321` can be; `0170****4321` and `0170****8765` cannot.
  bool sameAs(AccountReference other) {
    bool agree(String a, String b, {required bool atEnd}) {
      final (short, long) = a.length <= b.length ? (a, b) : (b, a);
      return atEnd ? long.endsWith(short) : long.startsWith(short);
    }

    final ends = end.isNotEmpty && other.end.isNotEmpty;
    final starts = start.isNotEmpty && other.start.isNotEmpty;
    if (!ends && !starts) return false;
    return (!ends || agree(end, other.end, atEnd: true)) &&
        (!starts || agree(start, other.start, atEnd: false));
  }

  /// `0170…4321`, or `…4321` when only the end shows.
  String get label {
    final tail = end.length > 4 && !masked
        ? end.substring(end.length - 4)
        : end;
    if (!masked) return '…$tail';
    if (tail.isEmpty) return '$start…';
    return start.isEmpty ? '…$tail' : '$start…$tail';
  }

  /// The last few digits shown, to tell accounts apart in a name: `4321`.
  String get lastDigits {
    final digits = end.isNotEmpty ? end : start;
    return digits.length > 4 ? digits.substring(digits.length - 4) : digits;
  }
}
