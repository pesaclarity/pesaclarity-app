import '../enums.dart';
import '../time/calendar.dart';

/// One transaction as the ledger rules see it: immutable, amounts in integer
/// minor units, with its payee's category already resolved.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.accountId,
    required this.occurredAt,
    required this.amountMinor,
    required this.direction,
    required this.kind,
    this.currency = 'KES',
    this.feeMinor = 0,
    this.payeeId,
    this.categoryId,
    this.categoryType,
    this.isDailySpending = false,
    this.transferPairId,
    this.payeeName,
    this.leakType = LeakType.none,
    this.tagIds = const {},
  }) : assert(amountMinor >= 0, 'amountMinor is always positive'),
       assert(feeMinor >= 0, 'feeMinor is always positive');

  final int id;
  final int accountId;
  final DateTime occurredAt;

  /// Always positive; [direction] says which way it moved.
  final int amountMinor;
  final TransactionDirection direction;
  final TransactionKind kind;
  final String currency;

  /// Transaction cost charged on top of [amountMinor], such as an M-Pesa fee.
  final int feeMinor;
  final int? payeeId;

  /// The category override, or else the payee's default category.
  final int? categoryId;
  final CategoryType? categoryType;

  /// Whether [categoryId] counts towards the day-to-day budget.
  final bool isDailySpending;

  /// The other half of an own-account transfer.
  final int? transferPairId;

  /// The payee's display name, when the payee is named.
  final String? payeeName;

  /// The payee's leak type; a category override does not change it.
  final LeakType leakType;

  /// Tags the user put on this transaction.
  final Set<int> tagIds;

  bool get isInflow => direction == TransactionDirection.inflow;

  bool get isOutflow => direction == TransactionDirection.outflow;

  /// The Nairobi calendar day this entry belongs to.
  CalendarDate get date => CalendarDate.nairobi(occurredAt);

  /// Amount with sign: positive in, negative out.
  int get signedMinor => isInflow ? amountMinor : -amountMinor;

  LedgerEntry copyWith({int? transferPairId}) => LedgerEntry(
    id: id,
    accountId: accountId,
    occurredAt: occurredAt,
    amountMinor: amountMinor,
    direction: direction,
    kind: kind,
    currency: currency,
    feeMinor: feeMinor,
    payeeId: payeeId,
    categoryId: categoryId,
    categoryType: categoryType,
    isDailySpending: isDailySpending,
    transferPairId: transferPairId ?? this.transferPairId,
    payeeName: payeeName,
    leakType: leakType,
    tagIds: tagIds,
  );

  @override
  String toString() =>
      'LedgerEntry($id, ${kind.name} ${direction.name} $amountMinor $currency)';
}
