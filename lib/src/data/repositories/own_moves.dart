import 'package:drift/drift.dart';

import '../../domain/accounts/mpesa_lines.dart';
import '../../domain/ledger/cross_currency_transfers.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/own_accounts.dart';
import '../../domain/ledger/own_transfers.dart';
import '../database/app_database.dart';
import 'app_settings_repository.dart';
import 'savings_links.dart';

/// Where a space's settings keep the person's answers to "Was this a move
/// between your accounts?", by sender ([moveSenderKey]): true for Yes.
const ownMoveAnswersKey = 'ledger.ownMoveAnswers';

/// The person's own numbers and accounts, from [accounts] (decision 0030,
/// rule 4). The accounts money between spaces keeps (decision 0027) are no
/// account a message can name: a payment on one is never an own transfer.
///
/// [linePhones] are the numbers the person typed for their M-Pesa lines,
/// by line id: a line's account has that number, so a send to it from
/// another line is a move between own accounts.
OwnAccounts ownAccountsOf(
  Iterable<Account> accounts, {
  Map<String, String> linePhones = const {},
}) => OwnAccounts([
  for (final a in accounts)
    if (!a.type.isBetweenSpaces)
      OwnAccount(
        id: a.id,
        reference: a.reference,
        institutionId: a.institutionId,
        phone: switch (lineOfReference(a.reference)) {
          final id? => linePhones[id],
          null => null,
        },
      ),
]);

/// Where each space's settings keep the numbers typed for M-Pesa lines,
/// by line id, copied from `mpesa.lines` so every space can match moves.
const linePhonesKey = 'mpesa.linePhones';

/// The line numbers [db]'s space keeps (see [linePhonesKey]).
Future<Map<String, String>> readLinePhones(AppDatabase db) async {
  final json = await DriftAppSettingsRepository(db).readJson(linePhonesKey);
  return {
    for (final MapEntry(:key, :value) in (json ?? const {}).entries)
      if (value is String) key: value,
  };
}

/// The answers the person gave, by sender.
Future<Map<String, bool>> readOwnMoveAnswers(AppDatabase db) async {
  final json = await DriftAppSettingsRepository(db).readJson(ownMoveAnswersKey);
  return {
    for (final MapEntry(:key, :value) in (json ?? const {}).entries)
      if (value is bool) key: value,
  };
}

/// Remembers [yes] as the answer for every move with [senderKey].
Future<void> rememberOwnMoveAnswer(
  AppDatabase db,
  String senderKey, {
  required bool yes,
}) async {
  final answers = await readOwnMoveAnswers(db);
  answers[senderKey] = yes;
  await DriftAppSettingsRepository(db).writeJson(ownMoveAnswersKey, answers);
}

/// A move between own accounts the app guessed from the amount and time
/// alone, for "Was this a move between your accounts?".
class OwnMoveQuestion {
  const OwnMoveQuestion({
    required this.outflowId,
    required this.inflowId,
    required this.senderKey,
    this.senderName,
  });

  final int outflowId;
  final int inflowId;

  /// Who the answer is remembered for ([moveSenderKey]).
  final String senderKey;

  /// The other side's name as the messages print it, when they do.
  final String? senderName;
}

/// [record] as matching sees it: amounts as stored, no category.
LedgerEntry moveEntryOf(TransactionRecord record) => LedgerEntry(
  id: record.id,
  accountId: record.accountId,
  occurredAt: record.occurredAt,
  amountMinor: record.amountMinor,
  direction: record.direction,
  kind: record.kind ?? TransactionKind.bank,
  currency: record.currency,
  feeMinor: record.feeMinor,
  transferPairId: record.transferPairId,
  transferAccountId: record.transferAccountId,
  source: record.source,
  counterpartyName: record.counterpartyName,
  counterpartyKind: record.counterpartyKind,
  counterpartyValue: record.counterpartyValue,
);

/// The paired own transfers in the space that are guesses
/// ([MoveCertainty.guess]) the person has not answered for, by each
/// side's id. Pairs with a savings account the app keeps and pairs across
/// currencies have rules of their own and are never asked about.
Future<Map<int, OwnMoveQuestion>> ownMoveQuestions(AppDatabase db) async {
  final t = db.transactions;
  final rows = await (db.select(
    t,
  )..where((t) => t.transferPairId.isNotNull())).get();
  if (rows.isEmpty) return const {};
  final byId = {for (final r in rows) r.id: r};
  final accounts = await db.select(db.accounts).get();
  final own = ownAccountsOf(accounts, linePhones: await readLinePhones(db));
  final references = {for (final a in accounts) a.id: a.reference};
  final answers = await readOwnMoveAnswers(db);
  final asked = <int, OwnMoveQuestion>{};
  for (final r in rows) {
    if (r.direction != TransactionDirection.outflow) continue;
    final partner = byId[r.transferPairId];
    if (partner == null || partner.transferPairId != r.id) continue;
    final out = moveEntryOf(r);
    final into = moveEntryOf(partner);
    if (isCrossCurrencyPair(out, into)) continue;
    final certainty = moveCertainty(
      out,
      into,
      references: references,
      receipts: {r.id: r.receiptNo, partner.id: partner.receiptNo},
      linked: {r.id: r.linkedReceiptNo, partner.id: partner.linkedReceiptNo},
      own: own,
      answers: answers,
    );
    if (certainty != MoveCertainty.guess) continue;
    if (await isSavingsLinked(db, r.id)) continue;
    final question = OwnMoveQuestion(
      outflowId: r.id,
      inflowId: partner.id,
      senderKey: moveSenderKey(out, into),
      senderName: moveSenderName(out, into),
    );
    asked[r.id] = question;
    asked[partner.id] = question;
  }
  return asked;
}

/// Unmatches every own transfer paired automatically that decision 0030's
/// rules now rule out ([movesApart]): a side names someone else's number,
/// prints a code the other side does not have, or the person said No for
/// its sender. Pairs the person made (an account they named, or a sender
/// they said Yes for), pairs with a savings account the app keeps and
/// pairs across currencies stay. They are not declined: they count as they
/// were, and can pair again with their right other side. Returns how many
/// were unmatched.
Future<int> unpairRuledOutMoves(AppDatabase db) async {
  final t = db.transactions;
  final rows = await (db.select(
    t,
  )..where((t) => t.transferPairId.isNotNull())).get();
  final byId = {for (final r in rows) r.id: r};
  final accounts = await db.select(db.accounts).get();
  final own = ownAccountsOf(accounts, linePhones: await readLinePhones(db));
  final references = {for (final a in accounts) a.id: a.reference};
  final answers = await readOwnMoveAnswers(db);
  var unpaired = 0;
  for (final r in rows) {
    if (r.direction != TransactionDirection.outflow) continue;
    final partner = byId[r.transferPairId];
    if (partner == null || partner.transferPairId != r.id) continue;
    if (r.transferAccountId != null || partner.transferAccountId != null) {
      continue;
    }
    final out = moveEntryOf(r);
    final into = moveEntryOf(partner);
    if (isCrossCurrencyPair(out, into)) continue;
    if (answers[moveSenderKey(out, into)] == true) continue;
    final receipts = {r.id: r.receiptNo, partner.id: partner.receiptNo};
    final linked = {
      r.id: r.linkedReceiptNo,
      partner.id: partner.linkedReceiptNo,
    };
    if (moveCertainty(
          out,
          into,
          references: references,
          receipts: receipts,
          linked: linked,
          own: own,
        ) ==
        MoveCertainty.code) {
      continue;
    }
    if (!movesApart(
      out,
      into,
      references: references,
      receipts: receipts,
      linked: linked,
      own: own,
      answers: answers,
    )) {
      continue;
    }
    if (await isSavingsLinked(db, r.id)) continue;
    await (db.update(t)..where((t) => t.id.isIn([r.id, partner.id]))).write(
      const TransactionsCompanion(transferPairId: Value(null)),
    );
    unpaired++;
  }
  return unpaired;
}
