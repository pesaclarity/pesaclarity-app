import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../domain/ledger/message_twins.dart';
import '../database/app_database.dart';
import 'app_settings_repository.dart';
import 'journal_repository.dart';
import 'message_links.dart';
import 'message_twins_store.dart';
import 'own_moves.dart';
import 'savings_links.dart';
import 'space_leak_repair.dart';
import 'transactions_repository.dart';

/// What one [repairBalances] run changed: notices merged into M-Pesa's
/// own messages, copies removed, own transfers the rules now rule out
/// unmatched, and own transfers paired.
typedef BalancesRepair = ({
  int walletCredits,
  int copies,
  int unpaired,
  int paired,
});

/// Where a space's settings keep the version of [repairBalances] it ran,
/// and the readers it ran for.
const balancesRepairKey = 'ledger.balancesRepaired';

/// The version of [repairBalances]: raised when it learns something new to
/// put right. Version 2 matches own transfers by decision 0030's rules;
/// version 3 brings the savings accounts in step with every payment, so
/// money moved to and from M-Shwari, Ziidi or Etica MMF, once the person
/// added it (decision 0026 item 5), is an own transfer. The accounts it
/// made before that was asked stay, as added; version 4 gives agent
/// withdrawals and deposits stored before they moved to and from a cash
/// account their side there ([linkStoredAgentCash]).
const balancesRepairVersion = 4;

/// The readers' versions as one text, such as `0.4.0 kcb@0.4.2,mpesa@0.5.0`:
/// the engine's [engine] and each pack's in [packs], by pack id, in order.
String readersVersion(String engine, Map<String, String> packs) {
  final ids = packs.keys.toList()..sort();
  return '$engine ${[for (final id in ids) '$id@${packs[id]}'].join(',')}';
}

/// Puts right, once per [balancesRepairVersion] and again whenever the
/// message readers change ([readers], see [readersVersion]; decision 0030,
/// rule 6), the money counted twice by earlier versions, keeping every
/// message:
///
/// * a bank's notice on M-Pesa and M-Pesa's own message for the same money
///   in ([TwinMatch.walletCredit]) kept as two transactions, which doubled
///   the wallet: merged as new messages now merge ([mergeStoredWalletCredits]);
/// * rows made twice from one message ([removeMessageCopies]);
/// * own transfers paired by amount and time that what the messages print
///   now rules out ([unpairRuledOutMoves]);
/// * money sent to or received from M-Shwari, Ziidi or Etica, stored as
///   plain payments: once the person added that product, each becomes an
///   own transfer with its account ([syncSavingsAccounts]); until they
///   answer, each waits as one (see `FamilyHold`). Payments the person
///   matched by hand or said went elsewhere stay as they are.
///
/// Then matches own transfers again over the whole history, with what the
/// readers now read, and reposts the whole journal from the records, which
/// reverses any entry the records no longer hold. Returns null when it had
/// already run for these readers.
///
/// With [spaces], first, once per [spaceLeakRepairVersion], takes out of
/// the space the copies of messages that the space reading their account
/// holds too ([removeLeakedCopies]).
Future<BalancesRepair?> repairBalancesOnce(
  AppDatabase db, {
  String? readers,
  SpacesOnPhone? spaces,
}) async {
  final settings = DriftAppSettingsRepository(db);
  if (spaces != null) {
    try {
      await repairSpaceLeakOnce(db, spaces);
    } on Object catch (error) {
      // Another space could not be opened: the repair runs again next
      // time, and the rest goes ahead now.
      if (kDebugMode) debugPrint('Repairing copies across spaces: $error');
    }
  }
  final done = await settings.readJson(balancesRepairKey);
  final version = done?['version'];
  if (version is int &&
      version >= balancesRepairVersion &&
      (readers == null || done?['readers'] == readers)) {
    return null;
  }
  final repaired = await repairBalances(db);
  await settings.writeJson(balancesRepairKey, {
    'version': balancesRepairVersion,
    'readers': ?readers ?? done?['readers'],
  });
  return repaired;
}

/// Where a space's settings keep the version of [removeLeakedCopies] it
/// ran.
const spaceLeakRepairKey = 'spaces.leakRepaired';

/// The version of the repair of messages stored in two spaces.
const spaceLeakRepairVersion = 1;

/// Runs [removeLeakedCopies] for [db] once per [spaceLeakRepairVersion].
/// Returns null when it had already run.
Future<LeakRepair?> repairSpaceLeakOnce(
  AppDatabase db,
  SpacesOnPhone spaces,
) async {
  final settings = DriftAppSettingsRepository(db);
  final done = (await settings.readJson(spaceLeakRepairKey))?['version'];
  if (done is int && done >= spaceLeakRepairVersion) return null;
  final repaired = await removeLeakedCopies(db, spaces);
  await settings.writeJson(spaceLeakRepairKey, {
    'version': spaceLeakRepairVersion,
  });
  return repaired;
}

/// The work of [repairBalancesOnce], safe to run again.
Future<BalancesRepair> repairBalances(AppDatabase db) async {
  final fixed = await db.transaction(
    () async => (
      copies: await removeMessageCopies(db),
      walletCredits: await mergeStoredWalletCredits(db),
      unpaired: await unpairRuledOutMoves(db),
    ),
  );
  // Turns the money moved to and from the M-Pesa family's accounts the
  // person has (decision 0026) into own transfers.
  await syncSavingsAccounts(db);
  await linkStoredAgentCash(db);
  final paired = await DriftTransactionsRepository(db).pairOwnTransfers();
  await JournalRepository.markForRebuild(db);
  await JournalRepository(db).sync();
  return (
    copies: fixed.copies,
    walletCredits: fixed.walletCredits,
    unpaired: fixed.unpaired,
    paired: paired,
  );
}

/// Merges each bank notice on M-Pesa into M-Pesa's own message for the
/// same money, as [findTwin] pairs them for new messages: the same
/// reference first, then the M-Pesa message naming the same sender, then
/// the nearest in time, one notice to one M-Pesa message. The M-Pesa
/// message stays the record (its receipt, time and balance) and keeps the
/// notice's message as its twin, so reading or clearing either treats them
/// as one. Returns how many notices were merged.
Future<int> mergeStoredWalletCredits(AppDatabase db) async {
  final t = db.transactions;
  final rows =
      await (db.select(t)
            ..where(
              (t) =>
                  t.direction.equalsValue(TransactionDirection.inflow) &
                  t.source.equalsValue(TransactionSource.sms) &
                  t.messageHash.isNotNull(),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.occurredAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();
  final taken = <int>{};
  var merged = 0;
  for (final notice in rows) {
    if (taken.contains(notice.id)) continue;
    if (!walletNoticeBanks.contains(packOf(notice.readBy))) continue;
    final incoming = twinFactsOf(notice);
    ({TransactionRecord record, TwinMatch match, bool named, Duration gap})?
    best;
    for (final wallet in rows) {
      if (wallet.id == notice.id ||
          wallet.accountId != notice.accountId ||
          taken.contains(wallet.id)) {
        continue;
      }
      final facts = twinFactsOf(wallet);
      final match = twinMatch(facts, incoming);
      if (match == null) continue;
      if (match == TwinMatch.walletCredit &&
          walletCreditSide(facts, incoming) != true) {
        continue;
      }
      final named = walletCreditNamesAgree(facts, incoming);
      final gap = wallet.occurredAt.difference(notice.occurredAt).abs();
      if (best == null ||
          match.index < best.match.index ||
          (match == best.match && named && !best.named) ||
          (match == best.match && named == best.named && gap < best.gap)) {
        best = (record: wallet, match: match, named: named, gap: gap);
      }
    }
    if (best == null) continue;
    final wallet = best.record;
    // A notice that already held a twin of its own: that message stays out
    // when the records are read again.
    if (notice.twinMessageHash case final extra?) {
      await db
          .into(db.setAsideMessages)
          .insertOnConflictUpdate(
            SetAsideMessagesCompanion.insert(messageHash: extra),
          );
    }
    await mergeTwin(db, wallet, notice.toCompanion(true), match: best.match);
    await _removeInto(db, notice, wallet);
    taken
      ..add(notice.id)
      ..add(wallet.id);
    merged++;
  }
  return merged;
}

/// Removes rows made twice from one message: a second row with the same
/// message as another, or one whose message another row already holds as
/// its twin. The oldest row stays. Returns how many were removed.
Future<int> removeMessageCopies(AppDatabase db) async {
  final rows = await (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  final byHash = <String, TransactionRecord>{};
  for (final r in rows) {
    if (r.messageHash case final h?) byHash.putIfAbsent(h, () => r);
  }
  var removed = 0;
  final gone = <int>{};
  for (final r in rows) {
    final hash = r.messageHash;
    if (hash == null) continue;
    final kept = byHash[hash]!;
    if (kept.id != r.id) {
      await _removeInto(db, r, kept);
      gone.add(r.id);
      removed++;
    }
  }
  for (final r in rows) {
    final twin = r.twinMessageHash;
    if (twin == null || gone.contains(r.id)) continue;
    final copy = byHash[twin];
    if (copy == null || copy.id == r.id || gone.contains(copy.id)) continue;
    if (copy.accountId != r.accountId || copy.amountMinor != r.amountMinor) {
      continue;
    }
    await _removeInto(db, copy, r);
    gone.add(copy.id);
    removed++;
  }
  return removed;
}

/// Removes [copy], the same money as [kept]: what the person set on the
/// copy and does not have on [kept] moves there, and so do its links.
Future<void> _removeInto(
  AppDatabase db,
  TransactionRecord copy,
  TransactionRecord kept,
) async {
  final now = await (db.select(
    db.transactions,
  )..where((t) => t.id.equals(kept.id))).getSingle();
  await (db.update(db.transactions)..where((t) => t.id.equals(kept.id))).write(
    TransactionsCompanion(
      categoryOverrideId: Value(
        now.categoryOverrideId ?? copy.categoryOverrideId,
      ),
      payeeId: Value(now.payeeId ?? copy.payeeId),
      item: Value(now.item ?? copy.item),
      goalId: Value(now.goalId ?? copy.goalId),
      debtId: Value(now.debtId ?? copy.debtId),
      lentLoanId: Value(now.lentLoanId ?? copy.lentLoanId),
      transferAccountId: Value(now.transferAccountId ?? copy.transferAccountId),
    ),
  );
  for (final table in ['sale_payments', 'quick_records']) {
    await db.customStatement(
      'UPDATE $table SET transaction_id = ? WHERE transaction_id = ?',
      [kept.id, copy.id],
    );
  }
  await db.customStatement(
    'INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) '
    'SELECT ?, tag_id FROM transaction_tags WHERE transaction_id = ?',
    [kept.id, copy.id],
  );
  await (db.update(db.transactions)
        ..where((t) => t.transferPairId.equals(copy.id)))
      .write(const TransactionsCompanion(transferPairId: Value(null)));
  await (db.delete(db.transactions)..where((t) => t.id.equals(copy.id))).go();
}
