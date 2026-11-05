import '../enums.dart';
import '../ledger/ledger_entry.dart';

/// How far a payment message's time may be from the sale it pays for. A
/// customer may pay just before the owner keys in the sale, or a little
/// after.
const saleMatchWindow = Duration(hours: 3);

/// An M-Pesa or bank part of a sale, waiting for its payment message.
class WaitingPayment {
  const WaitingPayment({
    required this.paymentId,
    required this.saleId,
    required this.method,
    required this.amountMinor,
    required this.currency,
    required this.soldAt,
    this.note,
  });

  final int paymentId;
  final int saleId;
  final SalePaymentMethod method;
  final int amountMinor;
  final String currency;
  final DateTime soldAt;
  final String? note;
}

/// The account types a payment by [method] arrives in; empty for cash and
/// credit, which never wait for a message.
Set<AccountType> accountTypesFor(SalePaymentMethod method) => switch (method) {
  SalePaymentMethod.mpesa => {AccountType.mpesa},
  SalePaymentMethod.bank => {AccountType.bank},
  SalePaymentMethod.cash || SalePaymentMethod.credit => const {},
};

/// Pairs each of [waiting], oldest sale first, with a payment in [entries]:
/// money in of the same amount and currency, on an account of the right
/// type, within [saleMatchWindow] of the sale, the closest in time first.
///
/// An entry already linked ([linked]), moved between the owner's own
/// accounts, or given another category by the owner or a payee is never
/// used, and each entry pays for one part only. [salesCategoryId] is the
/// category a match is filed under.
Map<int, int> matchWaitingPayments(
  Iterable<WaitingPayment> waiting,
  Iterable<LedgerEntry> entries, {
  required Map<int, AccountType> accountTypes,
  required Set<int> linked,
  required int salesCategoryId,
}) {
  final free = [
    for (final e in entries)
      if (e.isInflow &&
          e.transferPairId == null &&
          !linked.contains(e.id) &&
          (e.categoryId == null ||
              e.categoryIsAuto ||
              e.categoryId == salesCategoryId))
        e,
  ];
  final used = <int>{};
  final out = <int, int>{};
  final ordered = waiting.toList()
    ..sort((a, b) {
      final byTime = a.soldAt.compareTo(b.soldAt);
      return byTime != 0 ? byTime : a.paymentId.compareTo(b.paymentId);
    });
  for (final w in ordered) {
    final types = accountTypesFor(w.method);
    LedgerEntry? best;
    Duration? bestGap;
    for (final e in free) {
      if (used.contains(e.id) ||
          e.amountMinor != w.amountMinor ||
          e.currency != w.currency ||
          !types.contains(accountTypes[e.accountId])) {
        continue;
      }
      final gap = e.occurredAt.difference(w.soldAt).abs();
      if (gap > saleMatchWindow) continue;
      if (bestGap == null || gap < bestGap) {
        best = e;
        bestGap = gap;
      }
    }
    if (best != null) {
      used.add(best.id);
      out[w.paymentId] = best.id;
    }
  }
  return out;
}
