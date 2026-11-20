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
}

/// Why two messages on one account are taken to be the same money.
enum TwinMatch {
  /// Both print the same reference.
  receipt,

  /// One prints a reference and the other, a plain account alert, does not.
  alert,
}

/// Whether [incoming], a new message on the same account as [stored], is
/// about the same money, and why; null when they are two transactions.
///
/// Both must be messages, the same way, the same amount and currency.
/// Then:
///
/// * both print a reference: the same money only when it is the same
///   reference, within [sameReceiptWindow]. Different references are always
///   different payments;
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
    return a == b && gap <= sameReceiptWindow ? TwinMatch.receipt : null;
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
