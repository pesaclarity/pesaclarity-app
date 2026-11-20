import '../../core/money/money.dart';
import '../accounts/account_reference.dart';
import '../enums.dart';
import 'ledger_entry.dart';

/// An outflow from one of the user's accounts and the matching inflow into
/// another.
class TransferPair {
  const TransferPair(this.outflowId, this.inflowId);

  final int outflowId;
  final int inflowId;

  @override
  bool operator ==(Object other) =>
      other is TransferPair &&
      other.outflowId == outflowId &&
      other.inflowId == inflowId;

  @override
  int get hashCode => Object.hash(outflowId, inflowId);

  @override
  String toString() => 'TransferPair($outflowId -> $inflowId)';
}

const _outflowKinds = {
  TransactionKind.sent,
  TransactionKind.paybill,
  TransactionKind.bank,
};

const _inflowKinds = {TransactionKind.received, TransactionKind.bank};

/// Default gap allowed between the two halves of an own transfer. Bank
/// messages can arrive some minutes after the M-Pesa one.
const defaultTransferWindow = Duration(minutes: 30);

/// How long an own transfer the person named waits for its other side, and
/// how far apart a suggested match may be.
const waitingTransferWindow = Duration(days: 3);

/// The largest fee a transfer is taken to have cost when its message gives
/// none: KES 100, or 2% of the amount when that is more.
int transferFeeAllowanceMinor(int outflowMinor, String currency) {
  final floor = 100 * _pow10(minorUnitDigits(currency));
  final share = outflowMinor * 2 ~/ 100;
  return share > floor ? share : floor;
}

int _pow10(int digits) {
  var result = 1;
  for (var i = 0; i < digits; i++) {
    result *= 10;
  }
  return result;
}

/// How an outflow's amount relates to an inflow's.
enum TransferFit {
  /// The same amount.
  exact,

  /// The outflow is larger by its own fee, or by a plausible transfer fee
  /// when its message gave none.
  withFee,

  /// The outflow is larger by more than a plausible fee but within twice
  /// that: only ever suggested.
  loose,
}

/// How [outflow] and [inflow]'s amounts fit as one transfer, or null when
/// they cannot be one.
TransferFit? transferFit(LedgerEntry outflow, LedgerEntry inflow) {
  if (outflow.currency != inflow.currency) return null;
  final difference = outflow.amountMinor - inflow.amountMinor;
  if (difference == 0) return TransferFit.exact;
  if (difference < 0) return null;
  final allowance = outflow.feeMinor > 0
      ? outflow.feeMinor
      : transferFeeAllowanceMinor(outflow.amountMinor, outflow.currency);
  if (difference <= allowance) return TransferFit.withFee;
  final loose = transferFeeAllowanceMinor(
    outflow.amountMinor,
    outflow.currency,
  );
  return difference <= loose * 2 ? TransferFit.loose : null;
}

/// Whether [entry] may be one half of an own transfer: an unpaired move of
/// a kind transfers come as, not put in a non-transfer category.
bool _canPair(LedgerEntry entry) {
  if (entry.transferPairId != null || entry.isCorrection) return false;
  if (entry.transferAccountId != null) return true;
  final type = entry.categoryType;
  if (type != null && type != CategoryType.transfer) return false;
  return entry.isOutflow
      ? _outflowKinds.contains(entry.kind)
      : _inflowKinds.contains(entry.kind);
}

/// Whether the person's own naming of either side rules the pair out.
bool _namedApart(LedgerEntry out, LedgerEntry into) =>
    (out.transferAccountId != null &&
        out.transferAccountId != into.accountId) ||
    (into.transferAccountId != null && into.transferAccountId != out.accountId);

/// Whether either side was named as an own transfer by the person.
bool _named(LedgerEntry out, LedgerEntry into) =>
    out.transferAccountId != null || into.transferAccountId != null;

/// The account number [entry] paid into, as its message printed it: a
/// paybill's account reference (`131***4567` at KCB's paybill) or a bank
/// account sent to. Null when it names none.
String? paidToReference(LedgerEntry entry) {
  final value = entry.counterpartyValue;
  if (value == null) return null;
  return switch (entry.counterpartyKind) {
    PayeeIdentifierKind.paybill => switch (value.indexOf('#')) {
      final i when i >= 0 && i + 1 < value.length => value.substring(i + 1),
      _ => null,
    },
    PayeeIdentifierKind.account => value,
    _ => null,
  };
}

/// The bank account number [entry]'s message says the money came from or
/// went to (not a paybill reference, which may be a phone number). Null
/// when it names none.
String? _otherAccountNumber(LedgerEntry entry) =>
    entry.counterpartyKind == PayeeIdentifierKind.account
    ? entry.counterpartyValue
    : null;

/// Whether the account numbers the messages print rule [out] and [into]
/// out as one transfer: money in that names the bank account it came from,
/// when that is not [out]'s account, or money out that names the bank
/// account it went to, when that is not [into]'s.
bool _numberedApart(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, String?> references,
) {
  bool apart(String? printed, int accountId) {
    final named = AccountReference.tryParse(printed);
    final own = AccountReference.tryParse(references[accountId]);
    return named != null && own != null && !named.sameAs(own);
  }

  return apart(_otherAccountNumber(into), out.accountId) ||
      apart(_otherAccountNumber(out), into.accountId);
}

/// Whether [out] paid into the account [into] is on, by the number both
/// messages print: a masked `131***4567` and a full `1310004567` agree.
bool paidIntoAccount(
  LedgerEntry out,
  LedgerEntry into,
  Map<int, String?> references,
) {
  final paid = AccountReference.tryParse(paidToReference(out));
  final own = AccountReference.tryParse(references[into.accountId]);
  return paid != null && own != null && paid.sameAs(own);
}

/// Finds own-account transfers (bank to M-Pesa, M-Pesa to bank, money market
/// and savings moves) among entries not already paired.
///
/// Two entries pair when they are on different accounts, in the same
/// currency, one out and one in, no more than [window] apart in either
/// order, and the amounts are equal or the outflow is larger by a transfer
/// fee: its own fee when its message gave one, else up to
/// [transferFeeAllowanceMinor]. Only send, paybill and bank movements
/// qualify, and an entry the user has put in a non-transfer category is
/// left alone. An entry the person named as an own transfer pairs only with
/// the account they named, and waits up to [waitingTransferWindow]. Pairs
/// in [declined] were unmatched by the person and never pair again.
///
/// An outflow whose message names the account number it paid into, such as
/// an M-Pesa payment to a bank's paybill for a masked account, pairs with
/// money into the account with that number in [references] (each account's
/// number, by id) first, and waits as long as a named transfer. Money in
/// that names the bank account it came from never pairs with money out of
/// an account with another number, and the same the other way.
///
/// When several candidates fit, pairs confirmed by account number come
/// first, then equal amounts before ones with a fee,
/// then the closest in time, so each entry is used at most once and the
/// result does not depend on input order.
List<TransferPair> findOwnTransfers(
  Iterable<LedgerEntry> entries, {
  Duration window = defaultTransferWindow,
  Set<TransferPair> declined = const {},
  Map<int, String?> references = const {},
}) {
  final outflows = <String, List<LedgerEntry>>{};
  final inflows = <String, List<LedgerEntry>>{};
  for (final entry in entries) {
    if (!_canPair(entry)) continue;
    // Money typed in by hand pairs only when the person said where it went.
    if (entry.source == TransactionSource.manual &&
        entry.transferAccountId == null) {
      continue;
    }
    (entry.isOutflow ? outflows : inflows)
        .putIfAbsent(entry.currency, () => [])
        .add(entry);
  }

  final candidates = <(int, int, Duration, LedgerEntry, LedgerEntry)>[];
  for (final MapEntry(key: currency, value: outs) in outflows.entries) {
    final ins = inflows[currency];
    if (ins == null) continue;
    for (final out in outs) {
      for (final into in ins) {
        if (out.accountId == into.accountId) continue;
        if (_namedApart(out, into)) continue;
        if (_numberedApart(out, into, references)) continue;
        if (declined.contains(TransferPair(out.id, into.id))) continue;
        final fit = transferFit(out, into);
        if (fit == null || fit == TransferFit.loose) continue;
        final gap = out.occurredAt.difference(into.occurredAt).abs();
        final byNumber = paidIntoAccount(out, into, references);
        final allowed = _named(out, into) || byNumber
            ? waitingTransferWindow
            : window;
        if (gap <= allowed) {
          candidates.add((byNumber ? 0 : 1, fit.index, gap, out, into));
        }
      }
    }
  }
  candidates.sort((a, b) {
    final byNumber = a.$1.compareTo(b.$1);
    if (byNumber != 0) return byNumber;
    final byFit = a.$2.compareTo(b.$2);
    if (byFit != 0) return byFit;
    final byGap = a.$3.compareTo(b.$3);
    if (byGap != 0) return byGap;
    final byOut = a.$4.id.compareTo(b.$4.id);
    return byOut != 0 ? byOut : a.$5.id.compareTo(b.$5.id);
  });

  final used = <int>{};
  final pairs = <TransferPair>[];
  for (final (_, _, _, out, into) in candidates) {
    if (used.contains(out.id) || used.contains(into.id)) continue;
    used
      ..add(out.id)
      ..add(into.id);
    pairs.add(TransferPair(out.id, into.id));
  }
  return pairs;
}

/// An entry that may be the other side of an own transfer, and how well it
/// fits.
class TransferSuggestion {
  const TransferSuggestion({
    required this.partner,
    required this.fit,
    required this.gap,
  });

  final LedgerEntry partner;
  final TransferFit fit;
  final Duration gap;

  /// What the outflow cost over the inflow, for an entry of
  /// [entryAmountMinor]; zero for equal amounts.
  int feeMinor(int entryAmountMinor) =>
      (entryAmountMinor - partner.amountMinor).abs();
}

/// Entries that could be [entry]'s other side, best first: unpaired, on
/// another account, the opposite way, in the same currency, up to
/// [waitingTransferWindow] apart, with equal amounts or the outflow larger
/// by up to twice a plausible fee. For the person to choose; never paired
/// without them.
List<TransferSuggestion> suggestTransferPartners(
  LedgerEntry entry,
  Iterable<LedgerEntry> entries, {
  Set<TransferPair> declined = const {},
  int limit = 3,
}) {
  if (entry.transferPairId != null || entry.isCorrection) return const [];
  final found = <TransferSuggestion>[];
  for (final other in entries) {
    if (other.id == entry.id ||
        other.accountId == entry.accountId ||
        other.direction == entry.direction ||
        other.currency != entry.currency) {
      continue;
    }
    final out = entry.isOutflow ? entry : other;
    final into = entry.isOutflow ? other : entry;
    if (declined.contains(TransferPair(out.id, into.id))) continue;
    if (_namedApart(out, into)) continue;
    if (!_canPair(other)) continue;
    final fit = transferFit(out, into);
    if (fit == null) continue;
    final gap = out.occurredAt.difference(into.occurredAt).abs();
    if (gap > waitingTransferWindow) continue;
    found.add(TransferSuggestion(partner: other, fit: fit, gap: gap));
  }
  found.sort((a, b) {
    final byFit = a.fit.index.compareTo(b.fit.index);
    return byFit != 0 ? byFit : a.gap.compareTo(b.gap);
  });
  return found.take(limit).toList();
}

/// Returns [entries] with both halves of each pair pointing at each other.
List<LedgerEntry> applyTransferPairs(
  Iterable<LedgerEntry> entries,
  Iterable<TransferPair> pairs,
) {
  final partner = <int, int>{};
  for (final pair in pairs) {
    partner[pair.outflowId] = pair.inflowId;
    partner[pair.inflowId] = pair.outflowId;
  }
  return [
    for (final entry in entries)
      partner.containsKey(entry.id)
          ? entry.copyWith(transferPairId: partner[entry.id])
          : entry,
  ];
}
