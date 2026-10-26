import 'package:drift/drift.dart';

import '../../domain/enums.dart';

// Money columns are integer minor units (cents) and end in `Minor`.
// Enums are stored by name so reordering them never corrupts data.

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get openingDate => dateTime()();
}

@TableIndex(name: 'categories_key', columns: {#key}, unique: true)
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable key of a seeded category, shared with the categoriser's labels.
  /// Null for categories the user made.
  TextColumn get key => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 60).unique()();
  TextColumn get type => textEnum<CategoryType>()();

  /// Counts towards the day-to-day budget behind safe-to-spend.
  BoolColumn get isDailySpending =>
      boolean().withDefault(const Constant(false))();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40).unique()();
}

class Payees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get displayName => text().withLength(min: 1, max: 80)();
  IntColumn get defaultCategoryId =>
      integer().nullable().references(Categories, #id)();
  TextColumn get leakType =>
      textEnum<LeakType>().withDefault(Constant(LeakType.none.name))();
}

/// Raw identifiers that resolve to a payee, normalised by `PayeeIdentifier`.
/// Phone numbers are stored masked.
class PayeeIdentifiers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get payeeId =>
      integer().references(Payees, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<PayeeIdentifierKind>()();
  TextColumn get value => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {kind, value},
  ];
}

class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lender => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<DebtType>()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  IntColumn get startingBalanceMinor => integer()();

  /// Annual interest rate in basis points (1,250 = 12.5%). Null for no interest.
  IntColumn get annualRateBasisPoints => integer().nullable()();
  IntColumn get minimumPaymentMinor =>
      integer().withDefault(const Constant(0))();
  IntColumn get plannedPaymentMinor => integer().nullable()();

  /// False for family and friend loans, which get no interest maths.
  BoolColumn get isFormal => boolean().withDefault(const Constant(true))();
}

class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get targetMinor => integer()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      textEnum<GoalStatus>().withDefault(Constant(GoalStatus.active.name))();
}

@DataClassName('TransactionRecord')
@TableIndex(name: 'transactions_receipt_no', columns: {#receiptNo})
@TableIndex(
  name: 'transactions_account_time',
  columns: {#accountId, #occurredAt},
)
@TableIndex(
  name: 'transactions_counterparty',
  columns: {#counterpartyKind, #counterpartyValue},
)
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  DateTimeColumn get occurredAt => dateTime()();

  /// Always positive; [direction] says which way it moved.
  IntColumn get amountMinor => integer()();
  TextColumn get direction => textEnum<TransactionDirection>()();

  /// The parser's message type. Null for older rows and manual entries, which
  /// the ledger treats as [TransactionKind.bank].
  TextColumn get kind => textEnum<TransactionKind>().nullable()();
  IntColumn get feeMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();

  /// Exchange rate to the account currency in millionths, for foreign income.
  IntColumn get fxRateMicros => integer().nullable()();
  IntColumn get payeeId => integer().nullable().references(Payees, #id)();

  /// The other party's raw identifier, normalised by `PayeeIdentifier`, so
  /// naming a payee later reaches this transaction too.
  TextColumn get counterpartyKind =>
      textEnum<PayeeIdentifierKind>().nullable()();
  TextColumn get counterpartyValue => text().nullable()();
  TextColumn get item => text().nullable()();
  IntColumn get categoryOverrideId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get goalId => integer().nullable().references(Goals, #id)();
  IntColumn get debtId => integer().nullable().references(Debts, #id)();
  TextColumn get receiptNo => text().nullable()();
  TextColumn get source => textEnum<TransactionSource>()();

  /// Hash of the source SMS for dedupe; the message text itself is never kept.
  TextColumn get messageHash => text().nullable()();

  /// The other half of an own-account transfer, which never counts as spending.
  IntColumn get transferPairId =>
      integer().nullable().references(Transactions, #id)();
}

class TransactionTags extends Table {
  IntColumn get transactionId =>
      integer().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

class Recurring extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get frequency => textEnum<RecurrenceFrequency>()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get accountId => integer().nullable().references(Accounts, #id)();
}

/// One-offs and carried-forward arrears for a month (`yyyymm`, e.g. 202611).
class BudgetItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get month => integer()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get kind => textEnum<BudgetItemKind>()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
}

/// Frozen month-end results per category; a null category is Uncategorised.
class BudgetSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get month => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get plannedMinor => integer()();
  IntColumn get actualMinor => integer()();
  DateTimeColumn get frozenAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {month, categoryId},
  ];
}

/// Imported statements and how they reconciled to the closing balance.
class Imports extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  TextColumn get fileHash => text().unique()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  IntColumn get closingBalanceMinor => integer().nullable()();

  /// Statement closing balance minus the ledger balance; zero when it reconciles.
  IntColumn get reconciliationGapMinor => integer().nullable()();
  DateTimeColumn get importedAt => dateTime()();
}

/// Installed SMS parser packs from the ujumbe package.
class ParserPacks extends Table {
  TextColumn get packId => text()();
  TextColumn get version => text()();
  TextColumn get testStatus => textEnum<ParserPackTestStatus>().withDefault(
    Constant(ParserPackTestStatus.unknown.name),
  )();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get installedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {packId};
}
