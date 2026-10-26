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

/// Finds own-account transfers (bank to M-Pesa, M-Pesa to bank, money market
/// and savings moves) among entries not already paired.
///
/// Two entries pair when they are on different accounts, in the same currency,
/// for exactly the same amount, one out and one in, and no more than [window]
/// apart in either order. Only send, paybill and bank movements qualify, and
/// an entry the user has put in a non-transfer category is left alone. When
/// several candidates fit, the closest in time pair first, so each entry is
/// used at most once and the result does not depend on input order.
List<TransferPair> findOwnTransfers(
  Iterable<LedgerEntry> entries, {
  Duration window = defaultTransferWindow,
}) {
  final outflows = <(int, String), List<LedgerEntry>>{};
  final inflows = <(int, String), List<LedgerEntry>>{};
  for (final entry in entries) {
    if (entry.transferPairId != null) continue;
    final type = entry.categoryType;
    if (type != null && type != CategoryType.transfer) continue;
    final key = (entry.amountMinor, entry.currency);
    if (entry.isOutflow && _outflowKinds.contains(entry.kind)) {
      (outflows[key] ??= []).add(entry);
    } else if (entry.isInflow && _inflowKinds.contains(entry.kind)) {
      (inflows[key] ??= []).add(entry);
    }
  }

  final candidates = <(Duration, LedgerEntry, LedgerEntry)>[];
  for (final MapEntry(:key, value: outs) in outflows.entries) {
    final ins = inflows[key];
    if (ins == null) continue;
    for (final out in outs) {
      for (final into in ins) {
        if (out.accountId == into.accountId) continue;
        final gap = out.occurredAt.difference(into.occurredAt).abs();
        if (gap <= window) candidates.add((gap, out, into));
      }
    }
  }
  candidates.sort((a, b) {
    final byGap = a.$1.compareTo(b.$1);
    if (byGap != 0) return byGap;
    final byOut = a.$2.id.compareTo(b.$2.id);
    return byOut != 0 ? byOut : a.$3.id.compareTo(b.$3.id);
  });

  final used = <int>{};
  final pairs = <TransferPair>[];
  for (final (_, out, into) in candidates) {
    if (used.contains(out.id) || used.contains(into.id)) continue;
    used
      ..add(out.id)
      ..add(into.id);
    pairs.add(TransferPair(out.id, into.id));
  }
  return pairs;
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
