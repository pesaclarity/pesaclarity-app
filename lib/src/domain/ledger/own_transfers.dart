import '../../core/money/money.dart';
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
/// When several candidates fit, equal amounts pair before ones with a fee,
/// then the closest in time, so each entry is used at most once and the
/// result does not depend on input order.
List<TransferPair> findOwnTransfers(
  Iterable<LedgerEntry> entries, {
  Duration window = defaultTransferWindow,
  Set<TransferPair> declined = const {},
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

  final candidates = <(int, Duration, LedgerEntry, LedgerEntry)>[];
  for (final MapEntry(key: currency, value: outs) in outflows.entries) {
    final ins = inflows[currency];
    if (ins == null) continue;
    for (final out in outs) {
      for (final into in ins) {
        if (out.accountId == into.accountId) continue;
        if (_namedApart(out, into)) continue;
        if (declined.contains(TransferPair(out.id, into.id))) continue;
        final fit = transferFit(out, into);
        if (fit == null || fit == TransferFit.loose) continue;
        final gap = out.occurredAt.difference(into.occurredAt).abs();
        final allowed = _named(out, into) ? waitingTransferWindow : window;
        if (gap <= allowed) candidates.add((fit.index, gap, out, into));
      }
    }
  }
  candidates.sort((a, b) {
    final byFit = a.$1.compareTo(b.$1);
    if (byFit != 0) return byFit;
    final byGap = a.$2.compareTo(b.$2);
    if (byGap != 0) return byGap;
    final byOut = a.$3.id.compareTo(b.$3.id);
    return byOut != 0 ? byOut : a.$4.id.compareTo(b.$4.id);
  });

  final used = <int>{};
  final pairs = <TransferPair>[];
  for (final (_, _, out, into) in candidates) {
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
