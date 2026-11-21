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
}

/// Roles that never count as spending or income.
const neutralRoles = {
  LedgerRole.ownTransfer,
  LedgerRole.borrowing,
  LedgerRole.awaitingPayee,
  LedgerRole.correction,
};

/// Applies the spec's "rules that keep the numbers honest" to one entry.
///
/// Own transfers win over everything else. Inflows with a named payee are
/// classified by the payee's category type; a payee with no category counts
/// as income, shown as Uncategorised.
LedgerRole roleOf(LedgerEntry entry) {
  if (entry.kind == TransactionKind.correction) return LedgerRole.correction;
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
