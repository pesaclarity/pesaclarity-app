import 'package:drift/drift.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/payees/payee_identifier.dart';

/// The ledger's kind for a parser [type].
TransactionKind transactionKindFor(TransactionType type) => switch (type) {
  TransactionType.sent => TransactionKind.sent,
  TransactionType.received => TransactionKind.received,
  TransactionType.paybill => TransactionKind.paybill,
  TransactionType.till => TransactionKind.till,
  TransactionType.withdrawal => TransactionKind.withdrawal,
  TransactionType.airtime => TransactionKind.airtime,
  TransactionType.fuliza => TransactionKind.fulizaDraw,
  TransactionType.fulizaRepayment => TransactionKind.fulizaRepayment,
  TransactionType.loanRepayment => TransactionKind.loanRepayment,
  TransactionType.reversal => TransactionKind.reversal,
  TransactionType.bank => TransactionKind.bank,
};

/// The ledger's kind for [parsed]: as [transactionKindFor] its type, but
/// cash given to an M-Pesa agent, which the pack reads as money received,
/// is a cash deposit.
TransactionKind transactionKindOf(ParsedTransaction parsed) =>
    parsed.packId == 'mpesa' &&
        parsed.ruleId == 'deposit' &&
        parsed.direction == Direction.incoming
    ? TransactionKind.deposit
    : transactionKindFor(parsed.type);

TransactionDirection transactionDirectionFor(Direction direction) =>
    switch (direction) {
      Direction.incoming => TransactionDirection.inflow,
      Direction.outgoing => TransactionDirection.outflow,
    };

/// The other party of [parsed] as a normalised identifier, so a payee the
/// person names applies to it, or null when the message names no party
/// that can become a payee.
///
/// For bank alerts the `account` group is the account money went to when
/// the rule reads the person's own number as `own_account` too, and
/// otherwise may be their own account; for a loan repayment it is the
/// loan's number, and for reversals the receipt being reversed, so neither
/// of those is a counterparty. A bank's message about money sent or
/// received on M-Pesa can print the other side's bank account rather than a
/// phone number.
PayeeIdentifier? counterpartyIdentifier(ParsedTransaction parsed) {
  final name = parsed.counterparty;
  // The other side's code, such as Airtel's "Sender TID", names no party.
  final account = linkedReceiptOf(parsed) == null ? parsed.account : null;
  return switch (parsed.type) {
    TransactionType.sent || TransactionType.received =>
      account == null
          ? null
          : PayeeIdentifier.phone(account) ??
                (parsed.institution == null
                    ? null
                    : PayeeIdentifier.account(account)),
    // Only a rule that reads the person's own number apart can mean the
    // other side by `account`.
    TransactionType.bank =>
      account == null || parsed.ownAccount == null
          ? null
          : PayeeIdentifier.account(account),
    TransactionType.paybill =>
      name == null ? null : PayeeIdentifier.paybill(name, account),
    TransactionType.till => name == null ? null : PayeeIdentifier.till(name),
    _ => null,
  };
}

/// The other side's code [parsed] prints besides its own receipt, kept in
/// `account` by the rules that read one: Airtel Money's "Sender TID", the
/// M-Pesa ref in Equity's or KCB's send to a mobile wallet. M-Pesa's own
/// message for the same money prints it as its receipt, so the two sides
/// pair as one own transfer (decision 0030). Null when `account` is a
/// number (a phone, an account or a paybill account) rather than a code.
String? linkedReceiptOf(ParsedTransaction parsed) {
  final account = parsed.account?.trim().toUpperCase();
  if (account == null || account == parsed.receipt?.trim().toUpperCase()) {
    return null;
  }
  return switch (parsed.type) {
    TransactionType.received ||
    TransactionType.bank ||
    TransactionType.sent when isTransactionCode(account) => account,
    _ => null,
  };
}

/// Whether [text] is shaped as a transaction code: eight to twenty letters,
/// digits and dots, with at least one letter and one digit, such as
/// `TJA0000001` or `MP251114.1500.A00001`. Account and phone numbers are
/// digits, masked with `*`.
bool isTransactionCode(String text) =>
    RegExp(r'^[A-Z0-9.]{8,20}$').hasMatch(text) &&
    RegExp('[A-Z]').hasMatch(text) &&
    RegExp(r'\d').hasMatch(text);

/// [parsed] as a row for [accountId]. Keeps the parsed fields and the hash of
/// the message; the message text is not part of the row.
TransactionsCompanion transactionFromParsed(
  ParsedTransaction parsed, {
  required int accountId,
}) {
  final counterparty = counterpartyIdentifier(parsed);
  return TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: parsed.time,
    amountMinor: inCurrencyMinor(parsed.amountMinor, parsed.currency),
    direction: transactionDirectionFor(parsed.direction),
    kind: Value(transactionKindOf(parsed)),
    feeMinor: Value(inCurrencyMinor(parsed.feeMinor ?? 0, parsed.currency)),
    currency: Value(parsed.currency),
    counterpartyKind: Value(counterparty?.kind),
    counterpartyValue: Value(counterparty?.value),
    counterpartyName: Value(parsed.counterparty),
    receiptNo: Value(parsed.receipt),
    linkedReceiptNo: Value(linkedReceiptOf(parsed)),
    source: TransactionSource.sms,
    messageHash: Value(parsed.rawHash),
    dedupeKey: Value(parsed.dedupeKey),
    balanceAfterMinor: Value(
      parsed.balanceMinor == null
          ? null
          : inCurrencyMinor(parsed.balanceMinor!, parsed.currency),
    ),
    owedAfterMinor: Value(
      parsed.owedMinor == null
          ? null
          : inCurrencyMinor(parsed.owedMinor!, parsed.currency),
    ),
    owedDueAt: Value(parsed.due),
  );
}

/// [hundredths] (the parsers' and reader's minor units) in [currency]'s
/// own minor units: `150000` is UGX 1,500 but KES 1,500.00.
int inCurrencyMinor(int hundredths, String currency) => rescaleMinor(
  hundredths,
  fromDigits: 2,
  toDigits: minorUnitDigits(currency),
);
