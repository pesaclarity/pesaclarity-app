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
/// For bank alerts the `account` group is the person's own account, and for
/// reversals it is the receipt being reversed, so neither is a counterparty.
PayeeIdentifier? counterpartyIdentifier(ParsedTransaction parsed) {
  final name = parsed.counterparty;
  final account = parsed.account;
  return switch (parsed.type) {
    TransactionType.sent || TransactionType.received =>
      account == null ? null : PayeeIdentifier.phone(account),
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
    amountMinor: parsed.amountMinor,
    direction: transactionDirectionFor(parsed.direction),
    kind: Value(transactionKindFor(parsed.type)),
    feeMinor: Value(parsed.feeMinor ?? 0),
    currency: Value(parsed.currency),
    counterpartyKind: Value(counterparty?.kind),
    counterpartyValue: Value(counterparty?.value),
    counterpartyName: Value(parsed.counterparty),
    receiptNo: Value(parsed.receipt),
    source: TransactionSource.sms,
    messageHash: Value(parsed.rawHash),
    dedupeKey: Value(parsed.dedupeKey),
    balanceAfterMinor: Value(parsed.balanceMinor),
  );
}

/// [row] as its account counts it, in [currency]: the same amounts, in that
/// currency's minor units. Messages are read in their institution's usual
/// currency; an account the person set to another keeps the numbers.
TransactionsCompanion inAccountCurrency(
  TransactionsCompanion row,
  String currency,
) {
  if (!row.currency.present) return row.copyWith(currency: Value(currency));
  final from = row.currency.value;
  if (from == currency) return row;
  int scale(int minor) => rescaleMinor(
    minor,
    fromDigits: minorUnitDigits(from),
    toDigits: minorUnitDigits(currency),
  );
  final balance = row.balanceAfterMinor;
  return row.copyWith(
    currency: Value(currency),
    amountMinor: Value(scale(row.amountMinor.value)),
    feeMinor: row.feeMinor.present ? Value(scale(row.feeMinor.value)) : null,
    balanceAfterMinor: balance.present && balance.value != null
        ? Value(scale(balance.value!))
        : null,
  );
}
