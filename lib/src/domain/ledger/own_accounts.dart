import '../accounts/account_reference.dart';
import '../accounts/mpesa_lines.dart';
import '../enums.dart';
import '../payees/payee_identifier.dart';
import 'ledger_entry.dart';

/// One of the person's accounts as own-transfer matching sees it: its id
/// and the number its messages print, from the accounts list (decision
/// 0030, rule 4).
class OwnAccount {
  const OwnAccount({
    required this.id,
    this.reference,
    this.institutionId,
    this.phone,
  });

  final int id;

  /// The account number, or the phone number of a wallet, as kept on the
  /// account; null when none is known.
  final String? reference;

  /// The institution whose messages feed it, such as `mpesa` or `kcb`.
  final String? institutionId;

  /// The phone number the person typed for an M-Pesa line, whose reference
  /// is only the line's key.
  final String? phone;
}

/// The person's own numbers and accounts, learned from their accounts list:
/// which phone numbers, masked account numbers and bank paybill accounts
/// are theirs (decision 0030, rules 3 and 4).
class OwnAccounts {
  OwnAccounts(Iterable<OwnAccount> accounts)
    : _accounts = {for (final a in accounts) a.id: a};

  const OwnAccounts.none() : _accounts = const {};

  final Map<int, OwnAccount> _accounts;

  /// The phone number [accountId] is kept under, normalised as
  /// `PayeeIdentifier.phone` writes it (`0700000000`); null when its number
  /// is not a phone number or none is kept.
  String? phoneOf(int accountId) => _phoneOf(_accounts[accountId]);

  static String? _phoneOf(OwnAccount? a) =>
      a == null ? null : (a.phone ?? _phone(a.reference));

  /// The other own account [entry]'s message names as the other side: an
  /// own phone number, an own (masked) account number, or an own account
  /// paid at a paybill. Null when it names none of them, or more than one
  /// could be meant.
  int? namedBy(LedgerEntry entry) {
    final value = entry.counterpartyValue;
    if (value == null) return null;
    final found = <int>{};
    switch (entry.counterpartyKind) {
      case PayeeIdentifierKind.phone:
        final phone = AccountReference.tryParse(_phone(value));
        if (phone == null) return null;
        for (final a in _accounts.values) {
          final own = AccountReference.tryParse(_phoneOf(a));
          if (own != null && own.sameAs(phone)) found.add(a.id);
        }
      case PayeeIdentifierKind.account || PayeeIdentifierKind.paybill:
        final printed = AccountReference.tryParse(
          entry.counterpartyKind == PayeeIdentifierKind.account
              ? value
              : _paybillAccount(value),
        );
        if (printed == null) return null;
        for (final a in _accounts.values) {
          final own = AccountReference.tryParse(a.reference);
          if (own != null && own.sameAs(printed)) found.add(a.id);
        }
      case PayeeIdentifierKind.till || null:
        return null;
    }
    found.remove(entry.accountId);
    return found.length == 1 ? found.single : null;
  }

  /// Whether [entry] names a phone number as the other side that is not
  /// the phone number kept on [otherAccountId]: money to or from someone
  /// else, not the other account.
  bool namesAnotherPhone(LedgerEntry entry, int otherAccountId) {
    if (entry.counterpartyKind != PayeeIdentifierKind.phone) return false;
    final named = AccountReference.tryParse(_phone(entry.counterpartyValue));
    final own = AccountReference.tryParse(phoneOf(otherAccountId));
    return named != null && own != null && !named.sameAs(own);
  }

  /// [raw] as a phone number. The key of an M-Pesa line (`line:<id>`,
  /// decision 0026) is no number of the person's, whatever its id reads
  /// like, so it is never one.
  static String? _phone(String? raw) =>
      raw == null || lineOfReference(raw) != null
      ? null
      : PayeeIdentifier.phone(raw)?.value;

  static String? _paybillAccount(String value) {
    final i = value.indexOf('#');
    return i >= 0 && i + 1 < value.length ? value.substring(i + 1) : null;
  }
}

/// Who an own transfer guessed from [out] and [into] was with, as the
/// messages print it, for remembering the person's answer (decision 0030,
/// rule 5): the party the money came from, else the one it went to, else
/// the two accounts.
String moveSenderKey(LedgerEntry out, LedgerEntry into) {
  String? of(LedgerEntry e) {
    final kind = e.counterpartyKind;
    final value = e.counterpartyValue;
    if (kind != null && value != null && value.isNotEmpty) {
      return '${kind.name}:$value';
    }
    final name = e.counterpartyName
        ?.toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .trim();
    return name == null || name.isEmpty ? null : 'name:$name';
  }

  return of(into) ?? of(out) ?? 'accounts:${out.accountId}>${into.accountId}';
}

/// The other side as the messages print it, for the question: the name the
/// money came from, else the one it went to; null when neither names one.
String? moveSenderName(LedgerEntry out, LedgerEntry into) {
  for (final e in [into, out]) {
    final name = e.counterpartyName?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}
