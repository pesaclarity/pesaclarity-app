import '../enums.dart';
import '../ledger/ledger_entry.dart';

/// How far a payment message's time may be from the record it pays for. A
/// customer may pay just before the owner keys in the sale, or a little
/// after.
const saleMatchWindow = Duration(hours: 3);

/// What a waiting payment is for.
enum WaitingKind {
  /// Part of a sale: money in.
  sale,

  /// Stock or a cost bought: money out.
  bought,

  /// A customer paying what they owe: money in.
  gotPaid,

  /// Paying a supplier: money out.
  paid,

  /// The owner paying themselves into Personal: money out.
  paidYourself,

  /// Personal's side of Pay yourself: money in.
  payFromBusiness,

  /// Change sent back by M-Pesa or bank to a customer who paid too much:
  /// money out, taken off the sale.
  change;

  bool get isInflow =>
      this == sale || this == gotPaid || this == payFromBusiness;
}

/// An M-Pesa or bank payment recorded on the phone, waiting for its
/// message.
class WaitingPayment {
  const WaitingPayment({
    required this.id,
    required this.kind,
    required this.method,
    required this.amountMinor,
    required this.currency,
    required this.at,
    required this.categoryId,
    this.note,
    this.party,
  });

  /// The sale payment's id for a sale, else the record's id.
  final int id;
  final WaitingKind kind;
  final SalePaymentMethod method;
  final int amountMinor;
  final String currency;
  final DateTime at;

  /// The category the message is filed under once matched.
  final int categoryId;
  final String? note;

  /// The customer or supplier, as named.
  final String? party;

  @override
  bool operator ==(Object other) =>
      other is WaitingPayment && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// The account types a payment by [method] moves through; empty for cash
/// and credit, which never wait for a message.
Set<AccountType> accountTypesFor(SalePaymentMethod method) => switch (method) {
  SalePaymentMethod.mpesa => {AccountType.mpesa},
  SalePaymentMethod.bank => {AccountType.bank},
  SalePaymentMethod.cash || SalePaymentMethod.credit => const {},
};

/// Pairs each of [waiting], oldest first, with a payment message in
/// [entries]: the same direction, amount and currency, on an account of the
/// right type, within [saleMatchWindow] of the record, the closest in time
/// first.
///
/// An entry already linked ([linked]), moved between the owner's own
/// accounts, or given another category by the owner or a payee is never
/// used, and each entry pays for one record only.
Map<WaitingPayment, int> matchWaitingPayments(
  Iterable<WaitingPayment> waiting,
  Iterable<LedgerEntry> entries, {
  required Map<int, AccountType> accountTypes,
  required Set<int> linked,
}) {
  final free = [
    for (final e in entries)
      if (e.transferPairId == null && !linked.contains(e.id)) e,
  ];
  final used = <int>{};
  final out = <WaitingPayment, int>{};
  final ordered = waiting.toList()
    ..sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  for (final w in ordered) {
    final types = accountTypesFor(w.method);
    LedgerEntry? best;
    Duration? bestGap;
    for (final e in free) {
      if (used.contains(e.id) ||
          e.isInflow != w.kind.isInflow ||
          e.amountMinor != w.amountMinor ||
          e.currency != w.currency ||
          !types.contains(accountTypes[e.accountId]) ||
          !(e.categoryId == null ||
              e.categoryIsAuto ||
              e.categoryId == w.categoryId)) {
        continue;
      }
      final gap = e.occurredAt.difference(w.at).abs();
      if (gap > saleMatchWindow) continue;
      if (bestGap == null || gap < bestGap) {
        best = e;
        bestGap = gap;
      }
    }
    if (best != null) {
      used.add(best.id);
      out[w] = best.id;
    }
  }
  return out;
}

/// What happened to the rest when payments came to less than the sale.
enum ShortBy {
  /// The customer owes it.
  theyOweIt,

  /// The rest was paid in cash.
  restInCash,

  /// Another payment is still to come.
  anotherPayment,

  /// The owner gave a discount, so the sale is smaller.
  discount,

  /// The client kept back withholding tax and pays it to KRA: the sale
  /// stays whole and the rest counts as tax paid.
  taxWithheld,
}

/// What happened to the extra when payments came to more than the sale.
enum OverBy {
  changeInCash,
  changeByMpesa,

  /// The sale counts what was paid.
  keepWithSale,
}
