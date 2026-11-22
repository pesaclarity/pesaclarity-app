import 'package:drift/drift.dart';

import '../../domain/books/books.dart';
import '../../domain/enums.dart';
import '../../domain/people/reminder_text.dart';

// Money columns are integer minor units (cents) and end in `Minor`.
// Enums are stored by name so reordering them never corrupts data.

@TableIndex(name: 'accounts_institution', columns: {#institutionId})
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

  /// The account number its messages print, usually masked with a few
  /// digits at each end (`0170*****4321`). Tells two accounts at the same
  /// institution apart; null until a message shows one.
  TextColumn get reference => text().withLength(max: 40).nullable()();

  /// The savings product this account is, by its id in the app's list of
  /// savings products, such as `chumz`. The app keeps such an account
  /// itself, from the payments into it (see [SavingsPockets]). Null for
  /// every other account.
  TextColumn get product => text().withLength(min: 1, max: 40).nullable()();

  /// For a member of the M-Pesa family of accounts (decision 0026), such as
  /// M-Shwari, Ziidi or Pochi la Biashara: the M-Pesa wallet it belongs
  /// to, so two lines keep two families. Null for every other account.
  IntColumn get familyOf => integer().nullable()();

  /// For an account kept for money between spaces (decision 0027, see
  /// `AccountType.isBetweenSpaces`): the other space's id.
  TextColumn get linkedSpaceId => text().nullable()();

  /// For an account kept for money between spaces: the real account the
  /// money is on, by its id in the space where that account lives. In
  /// Personal, "Held for Vegetable stall" names Personal's own M-Pesa; in
  /// the business, "On your M-Pesa" names Personal's M-Pesa. Null for a
  /// purchase paid by another space.
  IntColumn get linkedAccountId => integer().nullable()();

  /// Left out of account lists (My accounts shows it under Hidden
  /// accounts). It still counts in totals and keeps its history.
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  /// Whether it counts in On hand and Safe to spend, as the person set it;
  /// null follows its type (savings accounts do not).
  BoolColumn get countsOnHand => boolean().nullable()();
}

/// A SACCO account's own details: one account holds its deposits and
/// shares (saved) and, through [loanDebtId], its loan (owed).
@DataClassName('SaccoDetailsRow')
class SaccoDetails extends Table {
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// Its M-Pesa paybill, digits only. Payments to it, or to the SACCO's
  /// name, are moves to the SACCO.
  TextColumn get paybill => text().withLength(max: 20).nullable()();

  /// Shares: counted in the account's balance and in Saved, but they
  /// cannot be withdrawn. Deposits are the balance less these.
  IntColumn get sharesMinor => integer().withDefault(const Constant(0))();
  IntColumn get contributionMinor => integer().nullable()();

  /// "You can borrow up to" this many tenths of deposits; null hides it.
  IntColumn get borrowTimesTenths => integer().nullable()();

  IntColumn get loanDebtId => integer().nullable().references(
    Debts,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The loan is taken off by check-off from salary, on [checkOffDay].
  BoolColumn get checkOff => boolean().withDefault(const Constant(false))();
  IntColumn get checkOffDay => integer().nullable()();

  /// Check-offs are taken from paydays after this instant.
  DateTimeColumn get checkOffFrom => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {accountId};
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

  /// When the next instalment is due, as `yyyymmdd`: from the lender's
  /// latest repayment message, or typed by the person. Null when not known.
  IntColumn get nextDueDay => integer().nullable()();

  /// When [nextDueDay] was set: the message's time, or when the person typed
  /// it. An older message does not replace it.
  DateTimeColumn get nextDueSetAt => dateTime().nullable()();

  /// The repayment whose message gave [nextDueDay]; null when typed.
  IntColumn get nextDueTransactionId => integer().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();
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

@TableIndex(
  name: 'goals_saved_in_pocket',
  columns: {#savedInPocketId},
  unique: true,
)
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

  /// The savings pocket the goal's money is kept in. What is saved is then
  /// what that pocket holds, not [savedMinor]. A pocket backs one goal.
  IntColumn get savedInPocketId => integer().nullable().references(
    SavingsPockets,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// One part of a savings account the app keeps (an [Accounts] row with a
/// `product`): the money paid in under one paybill account code, which the
/// savings app shows as one goal. An account with no codes has one pocket
/// with an empty [code].
@DataClassName('SavingsPocketRow')
class SavingsPockets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// The account code payments carry, such as `CH12345`; empty for money
  /// that carries none.
  TextColumn get code => text().withLength(max: 40)();
  TextColumn get name => text().withLength(min: 1, max: 80)();

  /// The start of the day the savings app unlocks it; null when it is open.
  DateTimeColumn get lockedUntil => dateTime().nullable()();

  /// The person said this code is not theirs: payments to it stay as they
  /// were counted and it holds nothing.
  BoolColumn get ignored => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {accountId, code},
  ];
}

/// The transactions on a savings account that the app keeps or the person
/// typed there, and the pocket each belongs to.
@DataClassName('SavingsEntryRow')
@TableIndex(name: 'savings_entries_pocket', columns: {#pocketId})
class SavingsEntries extends Table {
  IntColumn get transactionId =>
      integer().references(Transactions, #id, onDelete: KeyAction.cascade)();

  /// Null while money in or out is in no pocket yet, and for interest and
  /// corrections, which cover every pocket updated at their time.
  IntColumn get pocketId => integer().nullable().references(
    SavingsPockets,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get kind => textEnum<SavingsEntryKind>()();

  @override
  Set<Column> get primaryKey => {transactionId};
}

/// A balance the person typed for a pocket, as the savings app showed it.
/// Interest and corrections are worked out from these and the money paid in
/// and taken out, and worked out again whenever those change.
@DataClassName('SavingsReadingRow')
@TableIndex(
  name: 'savings_readings_pocket',
  columns: {#pocketId, #at},
  unique: true,
)
class SavingsReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pocketId =>
      integer().references(SavingsPockets, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get at => dateTime()();
  IntColumn get balanceMinor => integer()();

  /// False once the person says what the balance shows beyond the records
  /// is not interest. While true, the first balance typed for a pocket
  /// still counts as interest only when the gap is small (see
  /// `setupGapIsInterest`).
  BoolColumn get gapIsInterest => boolean().withDefault(const Constant(true))();

  /// Printed by a message, such as M-Shwari's balance in M-Pesa's message
  /// (decision 0026), rather than typed. It follows its message.
  BoolColumn get fromMessage => boolean().withDefault(const Constant(false))();
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
@TableIndex(name: 'transactions_message', columns: {#messageHash})
// Home, Activity, Plan and Insights read transactions by date alone.
@TableIndex(name: 'transactions_occurred_at', columns: {#occurredAt})
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

  /// The rate the person got for this transaction, in millionths: one
  /// [fxRateCurrency] bought this much of [currency]. Null uses the rates of
  /// the transaction's day.
  IntColumn get fxRateMicros => integer().nullable()();
  TextColumn get fxRateCurrency =>
      text().withLength(min: 3, max: 3).nullable()();
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

  /// Money lent to a friend or relative that this transaction is: money out
  /// that made the loan ("I lent this"), or money in that pays it back
  /// ("Paying me back"). Never spending or income. Removing the loan
  /// clears it (`LendingRepository.remove`).
  IntColumn get lentLoanId => integer().nullable()();
  TextColumn get receiptNo => text().nullable()();

  /// The other side's code as this message prints it, when it prints one
  /// besides its own receipt: Airtel Money's "Sender TID", the M-Pesa ref
  /// in a bank's send to a mobile wallet. The other side's message prints
  /// it as its receipt, so the two pair as one own transfer (decision 0030).
  TextColumn get linkedReceiptNo => text().nullable()();
  TextColumn get source => textEnum<TransactionSource>()();

  /// Hash of the source SMS for dedupe; the message text itself is never kept.
  TextColumn get messageHash => text().nullable()();

  /// Hash of a second message about the same money, merged into this one:
  /// a bank's plain debit alert and its transfer confirmation, say. A row
  /// takes at most one such twin without a shared receipt.
  TextColumn get twinMessageHash => text().nullable()();

  /// Receipt, amount and minute (ujumbe's `dedupeKey`), shared with statement
  /// imports so the same transaction is stored once per account.
  TextColumn get dedupeKey => text().nullable()();

  /// The account balance the message reported after this transaction.
  /// Only a parser rule or a statement sets it: it is a checkpoint.
  IntColumn get balanceAfterMinor => integer().nullable()();

  /// The balance of the person's other account that the message printed
  /// besides this one's: M-Shwari's, in M-Pesa's message moving money to
  /// or from it (decision 0026). It sets that account's balance.
  IntColumn get otherBalanceMinor => integer().nullable()();

  /// A balance read by the on-phone reader or typed while checking a
  /// message. Used only when it agrees with the checkpoint before it and
  /// the entries since; otherwise the balance check flags it.
  IntColumn get claimedBalanceMinor => integer().nullable()();

  /// What a Fuliza message said is owed in all after it ("Total Fuliza
  /// M-PESA outstanding amount"), and when it is due. A checkpoint on the
  /// Fuliza debt, as a reported balance is on the wallet.
  IntColumn get owedAfterMinor => integer().nullable()();
  DateTimeColumn get owedDueAt => dateTime().nullable()();

  /// The other half of an own-account transfer, which never counts as spending.
  IntColumn get transferPairId =>
      integer().nullable().references(Transactions, #id)();

  /// The person said this moved money to or from this other account of
  /// theirs. Until its other side is paired it waits, counted as an own
  /// transfer, never spending or income.
  IntColumn get transferAccountId => integer().nullable().references(
    Accounts,
    #id,
    onDelete: KeyAction.setNull,
  )();

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

  /// The readers that read this from its message: the engine and pack
  /// versions, such as `0.3.0 mpesa@0.3.1`. Null for rows from before it
  /// was kept, and for rows not read by the bundled readers.
  TextColumn get readBy => text().nullable()();

  /// The link both sides of money between spaces share (decision 0027): a
  /// switched payment and its balance record, the two sides of Pay
  /// yourself, or a purchase with the business's money and its Paid
  /// yourself. Written so that doing it twice changes nothing.
  TextColumn get linkId => text().nullable()();

  /// The space on the other side of [linkId].
  TextColumn get linkedSpaceId => text().nullable()();
}

/// What a payment switched to another space leaves on its account where
/// the account lives (decision 0027, section 2): only what the account's
/// balance needs. It is not a transaction: no list, total, report, search
/// or export reads it. The journal posts it against Held for that space,
/// and balances walk it with the account's transactions, so each reported
/// balance is still checked and the message is never read in again.
@DataClassName('BalanceRecord')
@TableIndex(name: 'balance_records_account', columns: {#accountId})
@TableIndex(name: 'balance_records_link', columns: {#linkId}, unique: true)
class BalanceRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get occurredAt => dateTime()();

  /// Always positive; [direction] says which way it moved.
  IntColumn get amountMinor => integer()();
  TextColumn get direction => textEnum<TransactionDirection>()();
  TextColumn get kind => textEnum<TransactionKind>().nullable()();
  IntColumn get feeMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('KES'))();

  /// The M-Pesa code or bank reference.
  TextColumn get receiptNo => text().nullable()();
  TextColumn get dedupeKey => text().nullable()();
  TextColumn get messageHash => text().nullable()();
  TextColumn get twinMessageHash => text().nullable()();

  /// The balance the message printed, a checkpoint as on a transaction.
  IntColumn get balanceAfterMinor => integer().nullable()();
  IntColumn get claimedBalanceMinor => integer().nullable()();
  IntColumn get owedAfterMinor => integer().nullable()();
  DateTimeColumn get owedDueAt => dateTime().nullable()();

  /// The id the payment had as a transaction here, which keeps its place
  /// among payments made at the same minute.
  IntColumn get transactionId => integer().nullable()();

  /// The link shared with the transaction in [spaceId].
  TextColumn get linkId => text()();

  /// The space the payment went to.
  TextColumn get spaceId => text()();
}

/// Own-transfer pairs the person unmatched, so pairing never makes them
/// again.
@DataClassName('DeclinedTransferRow')
class DeclinedTransfers extends Table {
  IntColumn get outflowId =>
      integer().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get inflowId =>
      integer().references(Transactions, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {outflowId, inflowId};
}

/// One entry of the space's double-entry journal (decision 0018): one money
/// event, from one source document. Entries are never edited or deleted: a
/// change posts an entry that [reverses] the old one, then a new entry.
@TableIndex(name: 'journal_entries_source', columns: {#sourceKind, #sourceId})
@TableIndex(name: 'journal_entries_reverses', columns: {#reverses})
@TableIndex(name: 'journal_entries_account', columns: {#accountId})
@DataClassName('JournalEntryRow')
class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// When the money moved. A reversal carries the date of the entry it
  /// reverses, so the two cancel out in every period.
  DateTimeColumn get occurredAt => dateTime()();

  /// What the entry was made from, and its id: a transaction, an account's
  /// opening, or the transaction whose reported balance it follows.
  TextColumn get sourceKind => textEnum<JournalSource>()();
  IntColumn get sourceId => integer()();
  TextColumn get memo => text().nullable()();

  /// The entry this one cancels, for a reversal.
  IntColumn get reverses =>
      integer().nullable().references(JournalEntries, #id)();

  /// When the entry was posted.
  DateTimeColumn get recordedAt => dateTime()();

  /// The money account the entry belongs to: its transaction's account, or
  /// the account it opens. Syncing reposts one account at a time by it.
  IntColumn get accountId => integer().nullable()();
}

/// Money accounts whose journal entries may be out of date: database
/// triggers add one whenever its transactions, the account itself, or a
/// payee or category its transactions use changes. Syncing reposts these
/// accounts only, then empties it.
@DataClassName('JournalDirtyRow')
class JournalDirty extends Table {
  IntColumn get accountId => integer()();

  @override
  Set<Column> get primaryKey => {accountId};
}

/// One line of a journal entry. An entry's postings sum to zero in each
/// currency.
@TableIndex(name: 'postings_entry', columns: {#entryId})
@TableIndex(name: 'postings_account', columns: {#account})
class Postings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer().references(JournalEntries, #id)();

  /// The account, by its key (see `BookAccount.key`), such as `money:3` or
  /// `notYetSorted`.
  TextColumn get account => text()();

  /// Signed: a debit is positive, a credit negative.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// The rate the person got for the transaction behind it, in millionths,
  /// as on the transaction. Null uses the rates of its day.
  IntColumn get rateMicros => integer().nullable()();
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

/// Messages whose transaction the person removed (a copy, or records they
/// cleared) or moved to another space, by message hash, so reading the
/// messages again never brings them back here: every message behind the
/// transaction, not only the first. A message merged into a transaction
/// that already keeps two is noted here at once, since the row has no place
/// for its hash (see `mergeTwin`).
@DataClassName('SetAsideMessage')
class SetAsideMessages extends Table {
  TextColumn get messageHash => text()();

  @override
  Set<Column> get primaryKey => {messageHash};
}

/// Exchange rates as first fetched each day, so each transaction converts at
/// the rates of its day.
@DataClassName('RateSnapshotRecord')
class RateSnapshots extends Table {
  /// The local date, as `2026-11-03`.
  TextColumn get day => text().withLength(min: 10, max: 10)();

  /// The rates as `ExchangeRates.toJson` writes them.
  TextColumn get rates => text()();

  @override
  Set<Column> get primaryKey => {day};
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

  /// The receipt's number, such as `VS-000245`, once a receipt is made.
  TextColumn get receiptNo => text().nullable()();
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

/// Another way an item is sold or bought besides the unit it is counted
/// in: a tot of a bottle, or a crate of bottles.
@DataClassName('MeasureRecord')
class ItemMeasures extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// [units] of this make [bases] of the item's unit: 30 tots make 1
  /// bottle, 1 crate makes 24 bottles.
  IntColumn get units => integer()();
  IntColumn get bases => integer()();

  /// What one sells for; null when it is only bought this way.
  IntColumn get priceMinor => integer().nullable()();

  /// What is left over of a thousandth of the item's unit after the last
  /// sale this way, so many small sales take stock out exactly.
  IntColumn get carry => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
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

  /// Thousandths of the item's unit, or of [measureId] when sold that way.
  IntColumn get quantityMilli => integer()();
  IntColumn get totalMinor => integer()();

  /// The way it was sold, such as a tot; null for the item's own unit.
  IntColumn get measureId => integer().nullable().references(
    ItemMeasures,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// A tab: rounds added for a table or a person, paid together at the end.
@DataClassName('TabRecord')
class Tabs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Such as Table 4 or a name.
  TextColumn get name => text().withLength(min: 1, max: 40)();
  DateTimeColumn get openedAt => dateTime()();

  /// When it was paid and closed; null while open.
  DateTimeColumn get closedAt => dateTime().nullable()();
}

/// One line of a round on a tab. Stock leaves when the tab is paid.
@DataClassName('TabLineRecord')
class TabLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get tabId =>
      integer().references(Tabs, #id, onDelete: KeyAction.cascade)();

  /// When the round was added.
  DateTimeColumn get at => dateTime()();
  IntColumn get itemId => integer().nullable().references(
    Items,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get measureId => integer().nullable().references(
    ItemMeasures,
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

/// A picture or document kept with the business for its receipts and
/// invoices: its logo, its M-PESA QR code, or an invoice's attachment. Kept
/// in the space's encrypted database, so it goes into its backup and is
/// never uploaded on its own.
@DataClassName('DocumentFileRecord')
class DocumentFiles extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `logo`, `mpesaQr` or `attachment`.
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  BlobColumn get bytes => blob()();
  DateTimeColumn get addedAt => dateTime()();

  /// The invoice an attachment goes with, in [position] order.
  IntColumn get invoiceId => integer().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Time logged for a client: what was done, on which day, for how long,
/// and whether it is billed.
@DataClassName('HourEntryRecord')
class HourEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get client => text()();
  TextColumn get project => text().nullable()();

  /// What was done, such as a meeting or a task.
  TextColumn get what => text()();

  /// The start of the day the work was done.
  DateTimeColumn get day => dateTime()();
  IntColumn get minutes => integer()();
  BoolColumn get billable => boolean().withDefault(const Constant(true))();

  /// The rate an hour when logged, for billing.
  IntColumn get rateMinor => integer().nullable()();

  /// The invoice that billed it; null until billed.
  IntColumn get invoiceId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// An invoice made on the phone. What it bills is in [InvoiceLines]; what
/// the client owes is a credit sale, so payments and the books follow it.
@DataClassName('InvoiceRecord')
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Such as `AC-INV-0018`.
  TextColumn get number => text()();
  TextColumn get client => text()();
  DateTimeColumn get issuedOn => dateTime()();
  DateTimeColumn get dueOn => dateTime().nullable()();
  TextColumn get billBy => text()();
  TextColumn get hoursDetail => text()();
  BoolColumn get timesheet => boolean().withDefault(const Constant(false))();
  TextColumn get withholding => text()();
  IntColumn get feesMinor => integer()();
  IntColumn get feesShownMinor => integer()();
  IntColumn get costsMinor => integer().withDefault(const Constant(0))();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get vatMinor => integer().withDefault(const Constant(0))();
  IntColumn get withheldMinor => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('KES'))();
  TextColumn get notes => text().nullable()();

  /// The credit sale that holds what the client owes.
  IntColumn get saleId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// One line of an invoice: fees (hours or items) or a cost passed on.
@DataClassName('InvoiceLineRecord')
class InvoiceLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get detail => text().nullable()();
  IntColumn get amountMinor => integer()();
  IntColumn get quantityMilli => integer().nullable()();
  IntColumn get unitMinor => integer().nullable()();
}

/// A business cost the owner has an eTIMS invoice for.
@DataClassName('EtimsCostRecord')
class EtimsCosts extends Table {
  IntColumn get transactionId =>
      integer().references(Transactions, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {transactionId};
}

/// Ask: one conversation in this space. Kept on this phone only, never in
/// backups (see `exportDatabase`).
@DataClassName('AskConversationRecord')
class AskConversations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// From the first understood question until the person renames it.
  TextColumn get title => text().withLength(min: 1, max: 80)();

  /// What the conversation is about now, as `AskContext` JSON.
  TextColumn get contextJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Ask: a question or a reply.
@DataClassName('AskMessageRecord')
@TableIndex(name: 'ask_messages_conversation', columns: {#conversationId})
class AskMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer().references(
    AskConversations,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// `person` or `reply`.
  TextColumn get role => text()();
  TextColumn get body => text()();

  /// What the reader made of a question, as `Understanding` JSON.
  TextColumn get understandingJson => text().nullable()();

  /// A reply's numbers, facts and "as of" time, as `AskAnswer` JSON.
  TextColumn get answerJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Ask: a word the person taught it, such as "john" for one payee.
@DataClassName('AskShortcutRecord')
class AskShortcuts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get word => text().withLength(min: 1, max: 60).unique()();

  /// A `SlotKind` name.
  TextColumn get entityKind => text()();

  /// The entity's Ask key, such as `p:12`.
  TextColumn get entityKey => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Transactions waiting to be sent to the person's own Firefly III
/// (decision 0029): one row per transaction, the latest change kept. The
/// database's triggers write it in the same write as the change, while the
/// space is being sent (see `createFireflyTriggers`).
@DataClassName('FireflyOutboxRow')
class FireflyOutbox extends Table {
  IntColumn get transactionId => integer()();

  /// `send` (make or change it there) or `delete`.
  TextColumn get action => text()();
  DateTimeColumn get queuedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Why Firefly III refused it, or why the last try failed.
  TextColumn get lastError => text().nullable()();

  /// Firefly III refused it: it waits for the next change to it.
  BoolColumn get refused => boolean().withDefault(const Constant(false))();
  DateTimeColumn get nextTryAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {transactionId};
}

/// What was sent to Firefly III for each transaction: its external id, the
/// Firefly III transaction group of each part, and a hash of what was sent.
/// In backups, so a restored phone sends nothing twice.
@DataClassName('FireflySentRow')
class FireflySent extends Table {
  IntColumn get transactionId => integer()();

  /// `pesaclarity:<space id>:<transaction id>`; kept when the transaction
  /// moves to another space.
  TextColumn get externalId => text()();

  /// The group id of each part, by its suffix, as JSON.
  TextColumn get groups => text()();
  TextColumn get hash => text()();

  /// The person deleted it in Firefly III: it is not sent again unless
  /// they choose Send everything again.
  BoolColumn get removedThere => boolean().withDefault(const Constant(false))();
  DateTimeColumn get sentAt => dateTime()();

  @override
  Set<Column> get primaryKey => {transactionId};
}

/// The Firefly III account each of the space's accounts, payees and
/// lenders was sent to, by its key (see `FireflyAccountSpec.key`).
@DataClassName('FireflyAccountRow')
class FireflyAccounts extends Table {
  TextColumn get key => text()();
  TextColumn get fireflyId => text()();
  TextColumn get name => text()();

  /// The opening balance and date it was made or last changed with.
  TextColumn get opening => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
