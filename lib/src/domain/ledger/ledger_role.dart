import '../enums.dart';
import 'ledger_entry.dart';

/// What an entry means for the user's money, after the honesty rules.
enum LedgerRole {
  /// Counts as spending.
  spending,

  /// Counts as income.
  income,

  /// A bank or wallet charge, counted as a fee.
  fee,

  /// Tax paid.
  tax,

  /// Money moved between the user's own accounts. Never spending or income.
  ownTransfer,

  /// Borrowed money arriving, such as a Fuliza draw or a family loan.
  borrowing,

  /// Paying back a debt. The Fuliza fee share is split out by
  /// [FulizaLedger].
  debtRepayment,

  /// Money put into savings.
  saving,

  /// Money received from someone the user has not named yet. Neutral until
  /// they say whether it was a gift, a loan or a repayment.
  awaitingPayee,

  /// A reversal or refund. Inflows reduce spending; outflows reduce income.
  reversal,

  /// A balance correction the person recorded: it sets an account's balance
  /// right and is never income, spending or tax.
  correction,

  /// Money between two spaces that is neither side's income or spending
  /// (decision 0027): what a payment switched to another space leaves where
  /// its account lives, or a correction of another space's part ("Set the
  /// stall's part"). Counts in neither money in nor money out.
  betweenSpaces,

  /// Money lent to a friend or relative, or their paying it back, linked to
  /// the loan in Lent and borrowed ("I lent this", "Paying me back"). It
  /// moves what they owe the person (Owed to you in the journal), so it is
  /// never spending or income, money in or money out.
  lending,
}

/// Roles that never count as spending or income.
const neutralRoles = {
  LedgerRole.ownTransfer,
  LedgerRole.borrowing,
  LedgerRole.awaitingPayee,
  LedgerRole.correction,
  LedgerRole.betweenSpaces,
  LedgerRole.lending,
};

/// Whether [entry] is money that arrived: income, or money from someone the
/// person has not named yet (it arrived, though it is not yet income, a
/// gift or a loan). Never own transfers (money moved between the person's
/// own accounts, savings included), borrowing (a Fuliza draw or a loan:
/// owed back, not earned), reversals and refunds (the person's own money
/// coming back, which lowers spending) or balance corrections. Money in as
/// Ask, Home's week by week and the income pattern count it; Activity's
/// Money in also lists borrowing and refunds.
bool isMoneyArrived(LedgerEntry entry) {
  if (!entry.isInflow) return false;
  final role = roleOf(entry);
  return role == LedgerRole.income || role == LedgerRole.awaitingPayee;
}

/// Applies the spec's "rules that keep the numbers honest" to one entry.
///
/// Own transfers win over everything else. Inflows with a named payee are
/// classified by the payee's category type; a payee with no category counts
/// as income, shown as Uncategorised.
LedgerRole roleOf(LedgerEntry entry) {
  if (entry.isBalanceRecord) return LedgerRole.betweenSpaces;
  if (entry.linkedSpaceId != null && entry.isCorrection) {
    return LedgerRole.betweenSpaces;
  }
  if (entry.kind == TransactionKind.correction) return LedgerRole.correction;
  if (entry.lentLoanId != null) return LedgerRole.lending;
  if (entry.transferPairId != null ||
      entry.transferAccountId != null ||
      entry.categoryType == CategoryType.transfer) {
    return LedgerRole.ownTransfer;
  }

  switch (entry.kind) {
    case TransactionKind.roundUp:
      return LedgerRole.ownTransfer;
    case TransactionKind.fulizaDraw:
      return LedgerRole.borrowing;
    case TransactionKind.fulizaRepayment || TransactionKind.loanRepayment:
      return LedgerRole.debtRepayment;
    case TransactionKind.charge:
      return entry.isInflow ? LedgerRole.reversal : LedgerRole.fee;
    case TransactionKind.reversal:
      return LedgerRole.reversal;
    case TransactionKind.correction:
      return LedgerRole.correction;
    // Cash taken out at an agent or put in: the person's own money moving
    // between the wallet and their hand, never spending or income, unless
    // they filed it under a category of their own.
    case TransactionKind.withdrawal when entry.categoryType == null:
      return LedgerRole.ownTransfer;
    case TransactionKind.deposit when entry.categoryType == null:
      return LedgerRole.ownTransfer;
    case TransactionKind.sent ||
        TransactionKind.received ||
        TransactionKind.paybill ||
        TransactionKind.till ||
        TransactionKind.withdrawal ||
        TransactionKind.deposit ||
        TransactionKind.airtime ||
        TransactionKind.bank:
      break;
  }

  if (entry.isInflow) {
    if (entry.kind == TransactionKind.received &&
        entry.payeeId == null &&
        entry.categoryType == null) {
      return LedgerRole.awaitingPayee;
    }
    return switch (entry.categoryType) {
      CategoryType.debt => LedgerRole.borrowing,
      CategoryType.savings => LedgerRole.ownTransfer,
      CategoryType.expense => LedgerRole.reversal,
      CategoryType.income ||
      CategoryType.tax ||
      CategoryType.transfer ||
      null => LedgerRole.income,
    };
  }

  return switch (entry.categoryType) {
    CategoryType.debt => LedgerRole.debtRepayment,
    CategoryType.savings => LedgerRole.saving,
    CategoryType.tax => LedgerRole.tax,
    CategoryType.income ||
    CategoryType.expense ||
    CategoryType.transfer ||
    null => LedgerRole.spending,
  };
}

/// What [entry] adds to spending as it reads alone: its amount when it is
/// spending, less a refund's (a reversal coming in), otherwise zero. The
/// one rule every spending figure (totals, categories, budgets, charts,
/// tags, summaries) follows, so they all add up to the same number.
int spendingOf(LedgerEntry entry) => switch (roleOf(entry)) {
  LedgerRole.spending => entry.amountMinor,
  LedgerRole.reversal when entry.isInflow => -entry.amountMinor,
  _ => 0,
};

/// What [entry] adds to income as it reads alone: its amount when it is
/// income, less money given back (a reversal going out), otherwise zero.
int incomeOf(LedgerEntry entry) => switch (roleOf(entry)) {
  LedgerRole.income when entry.isInflow => entry.amountMinor,
  LedgerRole.reversal when entry.isOutflow => -entry.amountMinor,
  _ => 0,
};

/// Whether [entry] is money moved into the person's own savings: an own
/// transfer out under a savings category, such as one into a savings
/// account of theirs (see `TransactionsRepository.ledgerEntries`) or a
/// payment to M-Shwari they said went to an account of their own. It is
/// still an own transfer, never spending, but it counts as saved, as it did
/// before it was matched, so a planned Savings line is met by it.
bool isSavedByTransfer(LedgerEntry entry) =>
    entry.isOutflow &&
    entry.categoryType == CategoryType.savings &&
    roleOf(entry) == LedgerRole.ownTransfer;

/// Whether Activity should ask the user to name this entry's payee.
///
/// Only person-to-person money with no payee yet; own transfers never ask.
bool needsPayeeName(LedgerEntry entry) =>
    entry.payeeId == null &&
    entry.transferPairId == null &&
    entry.transferAccountId == null &&
    entry.categoryType == null &&
    (entry.kind == TransactionKind.received ||
        entry.kind == TransactionKind.sent);
