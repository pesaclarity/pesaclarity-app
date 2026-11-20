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
  final account = parsed.account;
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
    kind: Value(transactionKindFor(parsed.type)),
    feeMinor: Value(inCurrencyMinor(parsed.feeMinor ?? 0, parsed.currency)),
    currency: Value(parsed.currency),
    counterpartyKind: Value(counterparty?.kind),
    counterpartyValue: Value(counterparty?.value),
    counterpartyName: Value(parsed.counterparty),
    receiptNo: Value(parsed.receipt),
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
