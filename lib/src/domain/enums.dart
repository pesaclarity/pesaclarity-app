/// Kinds of account the app tracks.
enum AccountType { bank, mpesa, sacco, moneyMarket, cash }

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
}

/// Where a transaction came from.
enum TransactionSource { sms, statement, manual }

/// Category kinds; only [expense] counts as spending.
enum CategoryType { income, expense, debt, savings, tax, transfer }

/// Leakage groups shown on Insights.
enum LeakType { lifestyle, friends, family, fees }

/// What a payee raw identifier is.
enum PayeeIdentifierKind { phone, till, paybill, account }

enum RecurrenceFrequency { weekly, monthly, quarterly, yearly }

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
}

enum GoalStatus { active, paused, achieved }

enum ParserPackTestStatus { unknown, passed, failed }
