import '../enums.dart';

/// A raw identifier for the other party of a transaction, normalised so the
/// same party always gives the same [value].
///
/// Institutions mask phone and account numbers differently, so masked digits
/// are kept as `*` and [matches] treats them as wildcards.
class PayeeIdentifier {
  const PayeeIdentifier._(this.kind, this.value);

  /// Rebuilds an identifier from a stored, already normalised [value].
  const PayeeIdentifier.stored(this.kind, this.value);

  /// A Kenyan mobile number, masked or not, in any of the usual forms
  /// (`0700 000 000`, `+254 700 000000`, `0700***000`, `2547xxxxx000`).
  ///
  /// Normalises to ten characters starting `07` or `01`. Returns null when
  /// [raw] is not shaped like a Kenyan mobile number.
  static PayeeIdentifier? phone(String raw) {
    var s = raw
        .replaceAll(RegExp('[xX•]'), '*')
        .replaceAll(RegExp(r'[^\d*]'), '');
    if (s.length == 12 && s.startsWith('254')) {
      s = '0${s.substring(3)}';
    } else if (s.length == 9 && (s.startsWith('7') || s.startsWith('1'))) {
      s = '0$s';
    }
    if (!RegExp(r'^0[17][\d*]{8}$').hasMatch(s)) return null;
    return PayeeIdentifier._(PayeeIdentifierKind.phone, s);
  }

  /// A Buy Goods till, by number or by the merchant name the message prints.
  static PayeeIdentifier? till(String raw) {
    final s = _name(raw);
    return s.isEmpty ? null : PayeeIdentifier._(PayeeIdentifierKind.till, s);
  }

  /// A paybill business, by number or printed name, with the account
  /// reference paid to. Without [account] the identifier covers every
  /// account at that business.
  static PayeeIdentifier? paybill(String business, [String? account]) {
    final b = _name(business);
    if (b.isEmpty || b.contains(_paybillSeparator)) return null;
    final a = account == null ? '' : _code(account);
    return PayeeIdentifier._(
      PayeeIdentifierKind.paybill,
      '$b$_paybillSeparator$a',
    );
  }

  /// A bank account number, masked or not.
  static PayeeIdentifier? account(String raw) {
    final s = _code(raw.replaceAll(RegExp('[xX•]'), '*'));
    return s.isEmpty ? null : PayeeIdentifier._(PayeeIdentifierKind.account, s);
  }

  static const _paybillSeparator = '#';

  final PayeeIdentifierKind kind;
  final String value;

  /// Whether some digits are hidden.
  bool get isMasked => value.contains('*');

  /// For a paybill, whether it covers every account at the business.
  bool get isWholeBusiness =>
      kind == PayeeIdentifierKind.paybill && value.endsWith(_paybillSeparator);

  /// Whether [other] could be the same party.
  ///
  /// Phones and accounts match position by position with `*` as a wildcard.
  /// A whole-business paybill matches any account at that business. Tills
  /// match exactly.
  bool matches(PayeeIdentifier other) {
    if (kind != other.kind) return false;
    if (value == other.value) return true;
    switch (kind) {
      case PayeeIdentifierKind.phone || PayeeIdentifierKind.account:
        if (value.length != other.value.length) return false;
        for (var i = 0; i < value.length; i++) {
          final a = value[i];
          final b = other.value[i];
          if (a != b && a != '*' && b != '*') return false;
        }
        return true;
      case PayeeIdentifierKind.paybill:
        final business = value.split(_paybillSeparator).first;
        final otherBusiness = other.value.split(_paybillSeparator).first;
        return business == otherBusiness &&
            (isWholeBusiness || other.isWholeBusiness);
      case PayeeIdentifierKind.till:
        return false;
    }
  }

  /// How the app shows this identifier, for example `0712***945`,
  /// `Till NAIVAS JUJA` or `Paybill KPLC, account 1234`.
  String get label => switch (kind) {
    PayeeIdentifierKind.phone || PayeeIdentifierKind.account => value,
    PayeeIdentifierKind.till => 'Till $value',
    PayeeIdentifierKind.paybill =>
      isWholeBusiness
          ? 'Paybill ${value.substring(0, value.length - 1)}'
          : 'Paybill ${value.replaceFirst(_paybillSeparator, ', account ')}',
  };

  @override
  bool operator ==(Object other) =>
      other is PayeeIdentifier && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'PayeeIdentifier(${kind.name} $value)';
}

String _name(String raw) => raw
    .trim()
    .replaceAll(RegExp(r'[.\s]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toUpperCase();

String _code(String raw) =>
    raw.replaceAll(RegExp(r'[^A-Za-z\d*]'), '').toUpperCase();
