import 'package:drift/drift.dart';

import '../../core/money/exchange_rates.dart';
import '../../core/money/money.dart';

import '../../domain/ledger/message_twins.dart';
import '../database/app_database.dart';

/// Finds a stored message on [row]'s account about the same money as
/// [row] (see [twinMatch]): the same reference first, then the nearest in
/// time. Null when [row] is a transaction of its own.
Future<TransactionRecord?> findTwin(
  AppDatabase db,
  TransactionsCompanion row,
) async {
  final hash = row.messageHash.present ? row.messageHash.value : null;
  if (hash == null) return null;
  if (row.source.present && row.source.value != TransactionSource.sms) {
    return null;
  }
  final at = row.occurredAt.value;
  final t = db.transactions;
  final nearby =
      await (db.select(t)..where(
            (t) =>
                t.accountId.equals(row.accountId.value) &
                t.amountMinor.equals(row.amountMinor.value) &
                t.direction.equalsValue(row.direction.value) &
                t.source.equalsValue(TransactionSource.sms) &
                t.messageHash.isNotNull() &
                t.occurredAt.isBetweenValues(
                  at.subtract(sameReceiptWindow),
                  at.add(sameReceiptWindow),
                ),
          ))
          .get();
  final incoming = _facts(
    at: at,
    amountMinor: row.amountMinor.value,
    direction: row.direction.value,
    currency: row.currency.present ? row.currency.value : 'KES',
    kind: row.kind.present ? row.kind.value : null,
    receipt: row.receiptNo.present ? row.receiptNo.value : null,
    messageHash: hash,
  );
  ({TransactionRecord record, TwinMatch match, Duration gap})? best;
  for (final record in nearby) {
    final match = twinMatch(
      _facts(
        at: record.occurredAt,
        amountMinor: record.amountMinor,
        direction: record.direction,
        currency: record.currency,
        kind: record.kind,
        receipt: record.receiptNo,
        messageHash: record.messageHash,
        twinHash: record.twinMessageHash,
      ),
      incoming,
    );
    if (match == null) continue;
    final gap = record.occurredAt.difference(at).abs();
    if (best == null ||
        match.index < best.match.index ||
        (match == best.match && gap < best.gap)) {
      best = (record: record, match: match, gap: gap);
    }
  }
  return best?.record;
}

TwinFacts _facts({
  required DateTime at,
  required int amountMinor,
  required TransactionDirection direction,
  required String currency,
  required TransactionKind? kind,
  required String? receipt,
  required String? messageHash,
  String? twinHash,
}) => TwinFacts(
  at: at,
  amountMinor: amountMinor,
  direction: direction,
  currency: currency,
  kind: kind ?? TransactionKind.bank,
  receipt: receipt,
  messageHash: messageHash,
  twinHash: twinHash,
);

/// Keeps one transaction for [stored] and [incoming], two messages about the
/// same money. The one that prints a reference wins: its reference, kind,
/// other party, fee and time (and so its dedupe key) are kept, and anything
/// it lacks, such as a balance, comes from the other. The account, and so
/// the account number the alert printed, stays. What the person set stays.
Future<void> mergeTwin(
  AppDatabase db,
  TransactionRecord stored,
  TransactionsCompanion incoming,
) {
  T? v<T>(Value<T?> value) => value.present ? value.value : null;
  final incomingHash = v(incoming.messageHash);
  final takeIncoming =
      (stored.receiptNo == null || stored.receiptNo!.isEmpty) &&
      (v(incoming.receiptNo)?.isNotEmpty ?? false);
  final incomingFee = v(incoming.feeMinor) ?? 0;
  final changes = takeIncoming
      ? TransactionsCompanion(
          occurredAt: incoming.occurredAt,
          kind: Value(v(incoming.kind) ?? stored.kind),
          receiptNo: incoming.receiptNo,
          dedupeKey: incoming.dedupeKey,
          feeMinor: Value(incomingFee > 0 ? incomingFee : stored.feeMinor),
          counterpartyKind: Value(
            v(incoming.counterpartyKind) ?? stored.counterpartyKind,
          ),
          counterpartyValue: Value(
            v(incoming.counterpartyValue) ?? stored.counterpartyValue,
          ),
          counterpartyName: Value(
            v(incoming.counterpartyName) ?? stored.counterpartyName,
          ),
          payeeId: Value(stored.payeeId ?? v(incoming.payeeId)),
          balanceAfterMinor: Value(
            v(incoming.balanceAfterMinor) ?? stored.balanceAfterMinor,
          ),
          owedAfterMinor: Value(
            v(incoming.owedAfterMinor) ?? stored.owedAfterMinor,
          ),
          owedDueAt: Value(v(incoming.owedDueAt) ?? stored.owedDueAt),
          twinMessageHash: Value(stored.twinMessageHash ?? incomingHash),
        )
      : TransactionsCompanion(
          feeMinor: Value(stored.feeMinor > 0 ? stored.feeMinor : incomingFee),
          counterpartyName: Value(
            stored.counterpartyName ?? v(incoming.counterpartyName),
          ),
          balanceAfterMinor: Value(
            stored.balanceAfterMinor ?? v(incoming.balanceAfterMinor),
          ),
          owedAfterMinor: Value(
            stored.owedAfterMinor ?? v(incoming.owedAfterMinor),
          ),
          owedDueAt: Value(stored.owedDueAt ?? v(incoming.owedDueAt)),
          twinMessageHash: Value(stored.twinMessageHash ?? incomingHash),
        );
  return (db.update(
    db.transactions,
  )..where((t) => t.id.equals(stored.id))).write(changes);
}

/// Finds the stored other half of a card payment in another currency, such
/// as a USD purchase on a KES account, and the account's own debit for it
/// in KES. Neither prints a reference, so they are one payment only when
/// both are plain money out of the same account within [twinWindow], one
/// in the account's currency and one not, neither already merged, and the
/// rate they imply is within [cardRateToleranceBasisPoints] of the day's.
/// Without that day's rate nothing is merged: the foreign amount then stays
/// out of totals, so it is not counted twice either.
Future<TransactionRecord?> findCardTwin(
  AppDatabase db,
  TransactionsCompanion row,
  CurrencyConverter? converter,
) async {
  final hash = row.messageHash.present ? row.messageHash.value : null;
  if (hash == null || converter == null) return null;
  if (row.direction.value != TransactionDirection.outflow) return null;
  if (row.receiptNo.present && (row.receiptNo.value?.isNotEmpty ?? false)) {
    return null;
  }
  final kind = row.kind.present ? row.kind.value : null;
  if (kind != null && kind != TransactionKind.bank) return null;
  final account = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(row.accountId.value))).getSingle();
  final currency = row.currency.present ? row.currency.value : 'KES';
  final at = row.occurredAt.value;
  final t = db.transactions;
  final nearby =
      await (db.select(t)..where(
            (t) =>
                t.accountId.equals(account.id) &
                t.direction.equalsValue(TransactionDirection.outflow) &
                t.source.equalsValue(TransactionSource.sms) &
                t.messageHash.isNotNull() &
                t.twinMessageHash.isNull() &
                t.receiptNo.isNull() &
                t.occurredAt.isBetweenValues(
                  at.subtract(twinWindow),
                  at.add(twinWindow),
                ),
          ))
          .get();
  int? inBase(int minor, String code) =>
      converter.convert(minor, code, at)?.baseMinor;
  ({TransactionRecord record, Duration gap})? best;
  for (final record in nearby) {
    if (record.messageHash == hash) continue;
    if ((record.kind ?? TransactionKind.bank) != TransactionKind.bank) {
      continue;
    }
    final foreign = record.currency != account.currency;
    if (foreign == (currency != account.currency)) continue;
    final (fMinor, fCode, aMinor) = foreign
        ? (record.amountMinor, record.currency, row.amountMinor.value)
        : (row.amountMinor.value, currency, record.amountMinor);
    final f = inBase(fMinor, fCode);
    final a = inBase(aMinor, account.currency);
    if (f == null || a == null) continue;
    if (!cardAmountsAgree(foreignInBase: f, accountInBase: a)) continue;
    final gap = record.occurredAt.difference(at).abs();
    if (best == null || gap < best.gap) best = (record: record, gap: gap);
  }
  return best?.record;
}

/// Keeps one transaction for a card payment in another currency and the
/// account's debit for it: the original amount and currency, the merchant,
/// and the rate the person got, the account's amount over the original.
Future<void> mergeCardTwin(
  AppDatabase db,
  TransactionRecord stored,
  TransactionsCompanion incoming,
) async {
  final account = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(stored.accountId))).getSingle();
  final incomingCurrency = incoming.currency.present
      ? incoming.currency.value
      : 'KES';
  final storedIsCard = stored.currency != account.currency;
  final cardMinor = storedIsCard
      ? stored.amountMinor
      : incoming.amountMinor.value;
  final cardCurrency = storedIsCard ? stored.currency : incomingCurrency;
  final accountMinor = storedIsCard
      ? incoming.amountMinor.value
      : stored.amountMinor;
  // One unit of the account's currency bought this much of the card's,
  // as the rate the person got is kept.
  final rate =
      cardMinor / accountMinor * _unitsRatio(account.currency, cardCurrency);
  final merchant = storedIsCard
      ? stored.counterpartyName
      : (incoming.counterpartyName.present
            ? incoming.counterpartyName.value
            : null);
  await (db.update(
    db.transactions,
  )..where((t) => t.id.equals(stored.id))).write(
    TransactionsCompanion(
      amountMinor: Value(cardMinor),
      currency: Value(cardCurrency),
      counterpartyName: Value(merchant ?? stored.counterpartyName),
      fxRateCurrency: Value(account.currency),
      fxRateMicros: Value((rate * 1e6).round()),
      twinMessageHash: Value(
        incoming.messageHash.present ? incoming.messageHash.value : null,
      ),
    ),
  );
}

/// Minor units of [accountCurrency] per minor unit of [cardCurrency], for
/// currencies with different numbers of decimals.
double _unitsRatio(String accountCurrency, String cardCurrency) {
  var ratio = 1.0;
  for (var d = minorUnitDigits(accountCurrency); d > 0; d--) {
    ratio *= 10;
  }
  for (var d = minorUnitDigits(cardCurrency); d > 0; d--) {
    ratio /= 10;
  }
  return ratio;
}
