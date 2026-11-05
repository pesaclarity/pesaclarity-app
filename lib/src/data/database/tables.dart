import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../domain/people/reminder_text.dart';

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

  /// Their money has meant different things, so money from them asks
  /// "What was this?" instead of taking [defaultCategoryId].
  BoolColumn get askPurpose => boolean().withDefault(const Constant(false))();
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

/// "Read messages like this the same way": the layout of a message the
/// person checked once, so later ones from the same institution are read
/// without asking. Holds the words around the fields, numbers only as their
/// layout, and the fields as empty slots: no amounts, names or dates.
@DataClassName('ReaderTemplateRow')
class ReaderTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get institutionId => text()();

  /// `ReadingTemplate.toJson`.
  TextColumn get template => text()();
  DateTimeColumn get createdAt => dateTime()();
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
/// Transactions moved to another space, by account and dedupe key, so
/// reading the same message again does not bring them back here.
@DataClassName('MovedTransaction')
class MovedTransactions extends Table {
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get dedupeKey => text()();
  TextColumn get spaceId => text()();

  @override
  Set<Column> get primaryKey => {accountId, dedupeKey};
}

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

/// A sale made with Sell. How it was paid is in [SalePayments].
@DataClassName('SaleRecord')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get soldAt => dateTime()();
  IntColumn get totalMinor => integer()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();

  /// What was sold, as the owner typed it; null for a plain amount.
  TextColumn get note => text().nullable()();
}

/// One way a sale was paid: cash in hand, an M-Pesa or bank payment matched
/// to its message, or what a customer owes.
@DataClassName('SalePaymentRecord')
@TableIndex(name: 'sale_payments_transaction', columns: {#transactionId})
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  TextColumn get method => textEnum<SalePaymentMethod>()();
  IntColumn get amountMinor => integer()();

  /// The cash entry made for it, or the payment message it matched. Null
  /// while an M-Pesa or bank payment waits for its message.
  IntColumn get transactionId => integer().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// What the customer owes, for a credit part.
  IntColumn get lentLoanId => integer().nullable().references(
    LentLoans,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// Bought, Got paid and Paid from a business's Today: how much, how the
/// money moved, and the cash entry made or the payment message matched.
@DataClassName('QuickRecord')
@TableIndex(name: 'quick_records_transaction', columns: {#transactionId})
class QuickRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<QuickRecordKind>()();
  DateTimeColumn get at => dateTime()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();

  /// Cash, M-Pesa or bank; credit for stock or a cost bought to pay later.
  TextColumn get method => textEnum<SalePaymentMethod>()();

  /// What was bought, for [QuickRecordKind.bought].
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The supplier or customer, as named.
  TextColumn get party => text().nullable()();
  TextColumn get note => text().nullable()();

  /// The supplier owed: made by a purchase on credit, or paid by Paid.
  IntColumn get debtId => integer().nullable().references(
    Debts,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The item restocked, for stock bought; its quantity is in
  /// [StockMoves].
  IntColumn get itemId => integer().nullable()();

  /// The cash entry made, or the payment message matched. Null while an
  /// M-Pesa or bank record waits for its message, and for credit.
  IntColumn get transactionId => integer().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// What a business sells: products with stock, and services. Quantities
/// are in thousandths of the unit, so 0.5 kg is 500.
@DataClassName('ItemRecord')
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<ItemKind>()();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// Such as kg, bunch or piece; null sells each.
  TextColumn get unit => text().nullable()();

  /// The selling price per unit; null when the price varies.
  IntColumn get priceMinor => integer().nullable()();

  /// Stock on hand in thousandths of [unit]; products only.
  IntColumn get stockMilli => integer().withDefault(const Constant(0))();

  /// The average cost of one unit, recalculated at each restock.
  IntColumn get averageCostMinor => integer().withDefault(const Constant(0))();

  /// "Warn me below", in thousandths of [unit].
  IntColumn get warnBelowMilli => integer().nullable()();

  /// A group for the Sell chips, such as Vegetables.
  TextColumn get grouping => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Every change to an item's stock: opening, sold, restocked or counted.
@DataClassName('StockMoveRecord')
class StockMoves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get at => dateTime()();
  TextColumn get kind => textEnum<StockMoveKind>()();

  /// Thousandths of the unit: up for opening and restock, down when sold.
  IntColumn get quantityMilli => integer()();

  /// What the move is worth at cost: what was paid for a restock, the
  /// average cost for a sale or count.
  IntColumn get costMinor => integer()();

  /// The sale it was part of.
  IntColumn get saleId => integer().nullable().references(
    Sales,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// The Bought record it came from.
  IntColumn get recordId => integer().nullable().references(
    QuickRecords,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get reason => textEnum<CountReason>().nullable()();
}

/// What a sale was made of: items, or an amount typed in.
@DataClassName('SaleLineRecord')
class SaleLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();

  /// Null for an "Other sale" amount.
  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get name => text()();
  IntColumn get quantityMilli => integer()();
  IntColumn get totalMinor => integer()();
}

/// A customer's or supplier's phone and how to remind them, by name, as
/// the People tab groups them.
@DataClassName('ContactRecord')
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Lowercased and trimmed, to find them by name.
  TextColumn get nameKey => text().unique()();
  TextColumn get name => text()();

  /// In full international form, such as +254712345678.
  TextColumn get phone => text().nullable()();
  TextColumn get sendWith => textEnum<SendWith>().nullable()();
}

/// A business's day closes: what the drawer should hold, what was counted,
/// and a note on any difference.
@DataClassName('DayCloseRecord')
class DayCloses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The start of the day closed, one close per day.
  DateTimeColumn get day => dateTime().unique()();
  IntColumn get expectedMinor => integer()();
  IntColumn get countedMinor => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get closedAt => dateTime()();
}

/// Tax a client kept back from a payment, such as 5% of consultancy fees,
/// and paid to KRA for the business. It counts as tax paid.
@DataClassName('WithheldTaxRecord')
class WithheldTaxes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The client, as named on their credit.
  TextColumn get person => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('KES'))();
  DateTimeColumn get at => dateTime()();

  /// The withholding certificate's number, once the client sends it.
  TextColumn get certificate => text().nullable()();
}
