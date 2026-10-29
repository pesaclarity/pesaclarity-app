import 'package:drift/drift.dart';

import '../../domain/enums.dart';

// Money columns are integer minor units (cents) and end in `Minor`.
// Enums are stored by name so reordering them never corrupts data.

@TableIndex(
  name: 'accounts_institution',
  columns: {#institutionId},
  unique: true,
)
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get openingDate => dateTime()();

  /// The institution whose messages feed this account, such as `mpesa`.
  /// Null for accounts added by hand.
  TextColumn get institutionId => text().nullable()();
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
@DataClassName('PayeeIdentifierRow')
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

@DataClassName('DebtRecord')
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

  /// A balance the user confirmed, such as from a lender statement, and
  /// when. Repayments after [balanceAsOf] come off it; without it they come
  /// off the starting balance.
  IntColumn get balanceMinor => integer().nullable()();
  DateTimeColumn get balanceAsOf => dateTime().nullable()();

  /// The payee repayments go to, for suggesting which debt a payment repays.
  IntColumn get payeeId => integer().nullable().references(Payees, #id)();

  /// Position in the user's own payoff order; null when not placed.
  IntColumn get customOrder => integer().nullable()();
}

/// Instalments agreed on a family or friend loan.
@DataClassName('DebtInstalmentRecord')
class DebtInstalments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get debtId =>
      integer().references(Debts, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get amountMinor => integer()();
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

  /// What has been put aside so far, as the user last recorded it.
  IntColumn get savedMinor => integer().withDefault(const Constant(0))();
}

/// Money the user lent to a friend or relative. Money borrowed from them is
/// a family debt in [Debts].
@DataClassName('LentLoanRecord')
class LentLoans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get person => text().withLength(min: 1, max: 80)();
  IntColumn get amountMinor => integer()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  DateTimeColumn get lentOn => dateTime()();

  /// When they agreed to pay it back; null when no date was agreed.
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().nullable()();
}

/// Part payments recorded by hand on a family or friend loan: either money
/// lent ([lentLoanId]) or a family debt ([debtId]), never both.
@DataClassName('LoanPaymentRecord')
class LoanPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get lentLoanId => integer().nullable().references(
    LentLoans,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get debtId => integer().nullable().references(
    Debts,
    #id,
    onDelete: KeyAction.cascade,
  )();
  DateTimeColumn get paidOn => dateTime()();
  IntColumn get amountMinor => integer()();

  @override
  List<String> get customConstraints => [
    'CHECK ((lent_loan_id IS NULL) != (debt_id IS NULL))',
  ];
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
@TableIndex(
  name: 'transactions_dedupe',
  columns: {#accountId, #dedupeKey},
  unique: true,
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

  /// The other party's name as the message printed it.
  TextColumn get counterpartyName => text().nullable()();
  TextColumn get item => text().nullable()();
  IntColumn get categoryOverrideId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get goalId => integer().nullable().references(Goals, #id)();
  IntColumn get debtId => integer().nullable().references(Debts, #id)();
  TextColumn get receiptNo => text().nullable()();
  TextColumn get source => textEnum<TransactionSource>()();

  /// Hash of the source SMS for dedupe; the message text itself is never kept.
  TextColumn get messageHash => text().nullable()();

  /// Receipt, amount and minute (ujumbe's `dedupeKey`), shared with statement
  /// imports so the same transaction is stored once per account.
  TextColumn get dedupeKey => text().nullable()();

  /// The account balance the message reported after this transaction.
  IntColumn get balanceAfterMinor => integer().nullable()();

  /// The other half of an own-account transfer, which never counts as spending.
  IntColumn get transferPairId =>
      integer().nullable().references(Transactions, #id)();

  /// The category predicted automatically by the on-device ML model or rules.
  IntColumn get autoCategoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Whether the prediction came from rules, model, or user correction.
  TextColumn get autoCategorySource =>
      textEnum<SuggestionSource>().nullable()();

  /// Prediction confidence score between 0.0 and 1.0.
  RealColumn get autoCategoryConfidence => real().nullable()();
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

/// Subscriptions the person tracks, and suggested ones they marked as
/// one-offs. A payee is tracked at most once.
@DataClassName('SubscriptionRow')
@TableIndex(name: 'subscriptions_payee', columns: {#payeeId}, unique: true)
class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// The payee whose charges this follows; null for one added by hand.
  IntColumn get payeeId => integer().nullable().references(Payees, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();
  TextColumn get frequency => textEnum<RecurrenceFrequency>()();

  /// When the next charge is expected, as last saved.
  DateTimeColumn get nextDate => dateTime()();
  TextColumn get status => textEnum<SubscriptionStatus>()();
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

  /// The institution whose statement this was, such as `mpesa`.
  TextColumn get institutionId => text().nullable()();
  IntColumn get openingBalanceMinor => integer().nullable()();

  /// Transactions read from the statement.
  IntColumn get transactionCount => integer().withDefault(const Constant(0))();

  /// Of [transactionCount], those new to the ledger.
  IntColumn get addedCount => integer().withDefault(const Constant(0))();

  /// Of [transactionCount], those already captured from SMS.
  IntColumn get duplicateCount => integer().withDefault(const Constant(0))();

  /// Table lines that could not be read, plus balances that did not follow.
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  TextColumn get result => textEnum<StatementImportResult>().nullable()();
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

/// Messages from a selected sender that no parser rule matched, waiting for
/// the person to tag their fields once.
///
/// This is the only place message text is kept: inside the encrypted
/// database, and only until the item is resolved, when [body] is cleared.
/// The hash stays so a later scan does not bring the message back.
@DataClassName('ReviewItem')
class ReviewItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The parser pack (and institution) that owns the sender.
  TextColumn get institutionId => text()();
  TextColumn get sender => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get messageHash => text().unique()();
  TextColumn get body => text().nullable()();

  /// Why the parser produced no transaction, for debugging packs.
  TextColumn get reason => text()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

/// Institutions the person ticked in My accounts. A row means it is switched
/// on; its sender IDs join the SMS watch list.
class SelectedInstitutions extends Table {
  /// Matches the ujumbe parser pack id, such as `mpesa`.
  TextColumn get institutionId => text().withLength(min: 1, max: 40)();
  DateTimeColumn get selectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {institutionId};
}

/// Small app-level settings, such as onboarding completion.
class AppSettings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 80)();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The category the person chose for a payee. The suggester reads this
/// before the categoriser, so their choice always wins for that payee.
@DataClassName('CategoryCorrection')
class CategoryCorrections extends Table {
  /// From `payeeKeys`: the named payee, raw identifier or tokenised name.
  TextColumn get payeeKey => text()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {payeeKey};
}

/// Each time the person accepts or changes a suggested category. Kept on the
/// phone as training examples: the encoded features, never the payee text.
@DataClassName('CategoryConfirmation')
class CategoryConfirmations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  /// What was suggested, if anything, and how sure and from where.
  IntColumn get suggestedCategoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  RealColumn get suggestedConfidence => real().nullable()();
  TextColumn get suggestionSource => textEnum<SuggestionSource>().nullable()();

  /// True when the person took the suggestion as it was.
  BoolColumn get accepted => boolean()();

  /// The model input as comma-separated integers.
  TextColumn get features => text()();
  IntColumn get featureSchemaVersion => integer()();
  DateTimeColumn get confirmedAt => dateTime()();
}
