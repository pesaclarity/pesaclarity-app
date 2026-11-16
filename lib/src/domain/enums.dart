/// Kinds of account the app tracks.
enum AccountType {
  bank,
  mpesa,
  sacco,
  moneyMarket,
  cash,

  /// An account added by hand that is none of the above.
  other,
}

/// Whether money came in or went out of an account.
enum TransactionDirection { inflow, outflow }

/// What kind of message or statement line a transaction came from.
///
/// Mirrors the ujumbe parser's transaction types, plus the noise kinds that
/// Activity collapses to one line per day.
enum TransactionKind {
  sent,
  received,
  paybill,
  till,
  withdrawal,
  deposit,
  airtime,
  fulizaDraw,
  fulizaRepayment,

  /// Small automatic moves into a money market fund, such as spare change.
  roundUp,

  /// A bank or wallet charge sent as its own message or statement line.
  charge,
  reversal,
  bank,

  /// The difference recorded when the person sets an account's real
  /// balance, or explains a gap between two reported balances. Neither
  /// income nor spending.
  correction,
}

/// Where a transaction came from.
enum TransactionSource { sms, statement, manual }

/// Category kinds; only [expense] counts as spending.
enum CategoryType { income, expense, debt, savings, tax, transfer }

/// Leakage groups shown on Insights; [none] is not a leak.
enum LeakType { none, lifestyle, friends, family, fees }

/// What a payee raw identifier is: a phone number, a Buy Goods till, a
/// paybill with its account reference, or a bank account number.
enum PayeeIdentifierKind { phone, till, paybill, account }

enum RecurrenceFrequency { weekly, monthly, quarterly, yearly }

/// Whether a repeat charge is tracked as a subscription, or was marked as a
/// one-off so it is not suggested again.
enum SubscriptionStatus { tracking, dismissed }

/// A budget line that is not a recurring bill.
enum BudgetItemKind { oneOff, carriedArrears }

enum DebtType {
  bankLoan,
  card,
  overdraft,
  salaryAdvance,
  fuliza,
  mobileLoan,
  saccoLoan,
  family,

  /// A business's supplier, for stock or costs bought to pay later.
  supplier,
}

enum GoalStatus { active, paused, achieved }

enum ParserPackTestStatus { unknown, passed, failed }

/// Where a category suggestion came from.
enum SuggestionSource {
  /// The person's own earlier choice for this payee.
  correction,

  /// The on-device categoriser model.
  model,

  /// Built-in payee defaults and rules, used when no model is installed.
  rules,
}

/// How an imported statement compared with the ledger.
enum StatementImportResult {
  /// The ledger balance matches the statement's closing balance.
  reconciled,

  /// The ledger is off from the statement's closing balance by some amount.
  gap,
}

/// How part of a sale was paid.
enum SalePaymentMethod {
  cash,
  mpesa,
  bank,

  /// The customer pays later.
  credit,
}

/// A record made from a business's Today: stock or a cost bought, a
/// customer paying what they owe, paying a supplier, the owner paying
/// themselves, or change sent back to a customer who paid too much.
enum QuickRecordKind { bought, gotPaid, paid, paidYourself, change }

/// What a business sells: something kept in stock, or its time or skill.
enum ItemKind { product, service }

/// Why an item's stock changed.
enum StockMoveKind {
  /// What was there when the item was added.
  opening,

  /// Sold: stock down at the average cost.
  sold,

  /// Bought to sell: stock up at what was paid.
  restocked,

  /// Counted: the difference from what the records said.
  counted,
}

/// Why a count came out different from the records.
enum CountReason {
  spoiled,
  used,
  lost,

  /// The records were wrong; not a cost.
  miscounted,
}
