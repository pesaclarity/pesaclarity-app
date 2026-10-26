/// Kinds of account the app tracks.
enum AccountType { bank, mpesa, sacco, moneyMarket, cash }

/// Whether money came in or went out of an account.
enum TransactionDirection { inflow, outflow }

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
