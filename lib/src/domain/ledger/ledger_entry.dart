import '../../core/money/money.dart';
import '../enums.dart';
import '../time/calendar.dart';

/// One transaction as the ledger rules see it: immutable, amounts in integer
/// minor units, with its payee's category already resolved.
class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.accountId,
    required this.occurredAt,
    required this.amountMinor,
    required this.direction,
    required this.kind,
    String? currency,
    this.feeMinor = 0,
    this.payeeId,
    this.categoryId,
    this.categoryType,
    this.isDailySpending = false,
    this.categoryIsAuto = false,
    this.needsPurpose = false,
    this.transferPairId,
    this.transferAccountId,
    this.source = TransactionSource.sms,
    this.payeeName,
    this.leakType = LeakType.none,
    this.tagIds = const {},
    this.counterpartyName,
    this.counterpartyKind,
    this.counterpartyValue,
    this.note,
    this.balanceAfterMinor,
    this.claimedBalanceMinor,
    this.owedAfterMinor,
    this.owedDueAt,
    this.originalAmountMinor,
    this.originalCurrency,
  }) : currency = currency ?? BaseCurrency.code,
       assert(amountMinor >= 0, 'amountMinor is always positive'),
       assert(feeMinor >= 0, 'feeMinor is always positive');

  final int id;
  final int accountId;

  /// The account balance the institution reported after this entry, such as
  /// M-Pesa's "New M-PESA balance". Null when the message gave none.
  final int? balanceAfterMinor;

  /// A balance the reader found or the person typed while checking the
  /// message: used only when it agrees with the checkpoint before it.
  final int? claimedBalanceMinor;

  /// For a Fuliza draw, what the message said is owed in all after it,
  /// daily charges included, and when it is due.
  final int? owedAfterMinor;
  final DateTime? owedDueAt;
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

  /// Whether [categoryId] was auto-assigned by ML/rules prediction.
  final bool categoryIsAuto;

  /// Money in from a payee whose money has meant different things, waiting
  /// for the person to say what it was.
  final bool needsPurpose;

  /// The other half of an own-account transfer.
  final int? transferPairId;

  /// The other account of an own transfer the person named, while (and
  /// after) it waits for its other side.
  final int? transferAccountId;

  /// Where it came from: a message, a statement or typed in.
  final TransactionSource source;

  /// The payee's display name, when the payee is named.
  final String? payeeName;

  /// The payee's leak type; a category override does not change it.
  final LeakType leakType;

  /// Tags the user put on this transaction.
  final Set<int> tagIds;

  /// The other party's name as the message printed it, or as typed for a
  /// manual entry.
  final String? counterpartyName;

  /// The other party's normalised identifier (see `PayeeIdentifier`), which
  /// naming a payee links to.
  final PayeeIdentifierKind? counterpartyKind;
  final String? counterpartyValue;

  /// What was bought or a note, when known.
  final String? note;

  /// The amount and currency the money actually moved in, when the entry
  /// was converted into the base currency.
  final int? originalAmountMinor;
  final String? originalCurrency;

  bool get isInflow => direction == TransactionDirection.inflow;

  bool get isOutflow => direction == TransactionDirection.outflow;

  /// The calendar day this entry belongs to, in the user's active timezone.
  CalendarDate get date => CalendarDate.of(occurredAt);

  /// Amount with sign: positive in, negative out.
  int get signedMinor => isInflow ? amountMinor : -amountMinor;

  /// Whether this is a balance correction rather than money that moved.
  bool get isCorrection => kind == TransactionKind.correction;

  LedgerEntry copyWith({int? transferPairId, int? accountId}) => LedgerEntry(
    id: id,
    accountId: accountId ?? this.accountId,
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
    categoryIsAuto: categoryIsAuto,
    needsPurpose: needsPurpose,
    transferPairId: transferPairId ?? this.transferPairId,
    transferAccountId: transferAccountId,
    source: source,
    payeeName: payeeName,
    leakType: leakType,
    tagIds: tagIds,
    counterpartyName: counterpartyName,
    counterpartyKind: counterpartyKind,
    counterpartyValue: counterpartyValue,
    note: note,
    balanceAfterMinor: balanceAfterMinor,
    claimedBalanceMinor: claimedBalanceMinor,
    owedAfterMinor: owedAfterMinor,
    owedDueAt: owedDueAt,
    originalAmountMinor: originalAmountMinor,
    originalCurrency: originalCurrency,
  );

  @override
  String toString() =>
      'LedgerEntry($id, ${kind.name} ${direction.name} $amountMinor $currency)';
}
