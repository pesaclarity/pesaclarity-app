import '../enums.dart';

/// How far apart two messages about the same money may be when only one of
/// them prints a reference. A bank's plain alert ("your acc ... has been
/// debited") and its own confirmation of the same transfer arrive minutes
/// apart (one when the transfer starts, one when it completes); fifteen
/// minutes covers a slow transfer while two separate payments of exactly
/// the same amount on one account in that time stay rare.
const twinWindow = Duration(minutes: 15);

/// How far apart two messages printing the same reference may be: a bank's
/// confirmation of an M-Pesa payment and M-Pesa's own message.
const sameReceiptWindow = Duration(days: 1);

/// What [twinMatch] compares about one stored or incoming message.
class TwinFacts {
  const TwinFacts({
    required this.at,
    required this.amountMinor,
    required this.direction,
    required this.currency,
    required this.kind,
    this.receipt,
    this.messageHash,
    this.twinHash,
    this.counterpartyName,
    this.readBy,
  });

  final DateTime at;
  final int amountMinor;
  final TransactionDirection direction;
  final String currency;
  final TransactionKind kind;
  final String? receipt;
  final String? messageHash;

  /// The message already merged into this one, for a stored row.
  final String? twinHash;

  /// The other party's name as the message printed it.
  final String? counterpartyName;

  /// The readers that read the message, such as `0.3.0 kcb@0.2.0`
  /// (see [packOf]).
  final String? readBy;
}

/// The pack that read a message, from its transaction's `readBy` such as
/// `0.3.0 kcb@0.2.0`; null when the bundled readers did not read it.
String? packOf(String? readBy) {
  if (readBy == null) return null;
  final parts = readBy.trim().split(' ');
  if (parts.length < 2) return null;
  final at = parts[1].indexOf('@');
  final pack = at < 0 ? parts[1] : parts[1].substring(0, at);
  return pack.isEmpty ? null : pack;
}

/// Banks that send their own message when money from an account with them
/// reaches an M-Pesa wallet, by the pack that reads it, with the name
/// M-Pesa's message gives the bank ("You have received Ksh2,500.00 from
/// KCB 1 522522").
const _walletCreditBanks = {'kcb': 'KCB'};

/// Why two messages on one account are taken to be the same money.
enum TwinMatch {
  /// Both print the same reference.
  receipt,

  /// One prints a reference and the other, a plain account alert, does not.
  alert,

  /// Money from a bank account into M-Pesa, told by both: the bank's own
  /// message ("... received from JANE DOE - 123****890 via KCB") and
  /// M-Pesa's ("... You have received Ksh2,500.00 from KCB 1 522522"). Each
  /// prints its own reference, so they never share one.
  walletCredit,
}

/// Whether [incoming], a new message on the same account as [stored], is
/// about the same money, and why; null when they are two transactions.
///
/// Both must be messages, the same way, the same amount and currency.
/// Then:
///
/// * both print a reference: the same money only when it is the same
///   reference, within [sameReceiptWindow]. Different references are
///   different payments, except for [TwinMatch.walletCredit]: money in
///   that a bank's pack read (KCB's "received from ... via KCB") and money
///   in that the M-Pesa pack read from that bank by name ("received ...
///   from KCB 1 522522"), both received, within [twinWindow], and [stored]
///   not already merged with another message;
/// * one prints a reference: the same money when they are within
///   [twinWindow], the one without is a plain alert (or the same kind), and
///   [stored] has not already taken a twin, so a second alert for the same
///   amount stays a payment of its own;
/// * neither prints one: never merged. Two plain alerts for the same amount
///   minutes apart are two payments.
TwinMatch? twinMatch(TwinFacts stored, TwinFacts incoming) {
  final storedHash = stored.messageHash;
  final incomingHash = incoming.messageHash;
  if (storedHash == null || incomingHash == null) return null;
  if (storedHash == incomingHash) return null;
  if (stored.direction != incoming.direction ||
      stored.amountMinor != incoming.amountMinor ||
      stored.currency != incoming.currency) {
    return null;
  }
  final gap = stored.at.difference(incoming.at).abs();
  final a = _reference(stored.receipt);
  final b = _reference(incoming.receipt);
  if (a != null && b != null) {
    if (a == b) return gap <= sameReceiptWindow ? TwinMatch.receipt : null;
    if (gap > twinWindow) return null;
    if (stored.twinHash != null && stored.twinHash != incomingHash) {
      return null;
    }
    return walletCreditSide(stored, incoming) != null
        ? TwinMatch.walletCredit
        : null;
  }
  if (a == null && b == null) return null;
  if (gap > twinWindow) return null;
  if (stored.twinHash != null && stored.twinHash != incomingHash) return null;
  final plain = a == null ? stored : incoming;
  final rich = a == null ? incoming : stored;
  if (plain.kind != TransactionKind.bank && plain.kind != rich.kind) {
    return null;
  }
  return TwinMatch.alert;
}

/// For two messages about money into M-Pesa from a bank account (see
/// [TwinMatch.walletCredit]): true when [first] is M-Pesa's own message
/// and [second] the bank's, false the other way, null when they are not
/// such a pair.
bool? walletCreditSide(TwinFacts first, TwinFacts second) {
  if (first.direction != TransactionDirection.inflow ||
      first.kind != TransactionKind.received ||
      second.kind != TransactionKind.received) {
    return null;
  }
  bool fromBank(TwinFacts wallet, TwinFacts bank) {
    if (packOf(wallet.readBy) != 'mpesa') return false;
    final name = _walletCreditBanks[packOf(bank.readBy)];
    if (name == null) return false;
    final printed = wallet.counterpartyName?.trim().toUpperCase() ?? '';
    return printed.split(RegExp(r'\s+')).first == name;
  }

  if (fromBank(first, second)) return true;
  if (fromBank(second, first)) return false;
  return null;
}

String? _reference(String? receipt) {
  final r = receipt?.trim().toUpperCase();
  return r == null || r.isEmpty ? null : r;
}

/// How far the rate a card payment and its account debit imply may be from
/// the day's rate for the two to be taken as one payment: 10%, room for a
/// bank's conversion margin and fees.
const cardRateToleranceBasisPoints = 1000;

/// Whether a card payment of [foreignMinor] in another currency and an
/// account debit of [accountMinor] in the account's currency, both shown in
/// the base currency as [foreignInBase] and [accountInBase], are about the
/// same money by amount: within [cardRateToleranceBasisPoints] of each
/// other.
bool cardAmountsAgree({
  required int foreignInBase,
  required int accountInBase,
}) {
  if (foreignInBase <= 0 || accountInBase <= 0) return false;
  final gap = (foreignInBase - accountInBase).abs();
  return gap * 10000 <= accountInBase * cardRateToleranceBasisPoints;
}
