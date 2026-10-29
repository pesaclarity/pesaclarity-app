import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/ledger_entry.dart';

/// Predicts categories for transactions and writes confident predictions to
/// the local database as intelligent storage for on-device learning & federated ML.
class AutoCategoriser {
  AutoCategoriser(this._db);

  final AppDatabase _db;

  /// Runs predictions on eligible transactions using [suggester].
  ///
  /// Can be constrained to specific [transactionIds] or a specific [payeeId].
  /// Processes transactions in batches of 200 within atomic transactions.
  Future<int> autoCategorise(
    CategorySuggester suggester, {
    Iterable<int>? transactionIds,
    int? payeeId,
  }) async {
    final t = _db.transactions;
    final p = _db.payees;

    final query = _db.select(t).join([
      leftOuterJoin(p, p.id.equalsExp(t.payeeId)),
    ]);

    final conditions = <Expression<bool>>[t.categoryOverrideId.isNull()];

    if (transactionIds != null) {
      conditions.add(t.id.isIn(transactionIds));
    }
    if (payeeId != null) {
      conditions.add(t.payeeId.equals(payeeId));
    }

    query.where(conditions.reduce((a, b) => a & b));

    final rows = await query.get();
    var changed = 0;
    const batchSize = 200;

    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.skip(i).take(batchSize).toList();
      await _db.transaction(() async {
        for (final row in batch) {
          final tx = row.readTable(t);
          final payee = row.readTableOrNull(p);

          if (payee?.defaultCategoryId != null) {
            if (tx.autoCategoryId != null ||
                tx.autoCategorySource != null ||
                tx.autoCategoryConfidence != null) {
              await (_db.update(
                _db.transactions,
              )..where((tbl) => tbl.id.equals(tx.id))).write(
                const TransactionsCompanion(
                  autoCategoryId: Value(null),
                  autoCategorySource: Value(null),
                  autoCategoryConfidence: Value(null),
                ),
              );
              changed++;
            }
            continue;
          }

          final entry = LedgerEntry(
            id: tx.id,
            accountId: tx.accountId,
            occurredAt: tx.occurredAt,
            amountMinor: tx.amountMinor,
            direction: tx.direction,
            kind: tx.kind ?? TransactionKind.bank,
            currency: tx.currency,
            feeMinor: tx.feeMinor,
            payeeId: tx.payeeId,
            payeeName: payee?.displayName,
            counterpartyName: tx.counterpartyName,
            counterpartyKind: tx.counterpartyKind,
            counterpartyValue: tx.counterpartyValue,
            note: tx.item,
          );

          final suggestion = suggester.suggest(entry);
          final int? newAutoId;
          final SuggestionSource? newSource;
          final double? newConfidence;

          if (autoApplies(suggestion)) {
            newAutoId = suggestion!.categoryId;
            newSource = suggestion.source;
            newConfidence = suggestion.confidence;
          } else {
            newAutoId = null;
            newSource = null;
            newConfidence = null;
          }

          if (tx.autoCategoryId != newAutoId ||
              tx.autoCategorySource != newSource ||
              tx.autoCategoryConfidence != newConfidence) {
            await (_db.update(
              _db.transactions,
            )..where((tbl) => tbl.id.equals(tx.id))).write(
              TransactionsCompanion(
                autoCategoryId: Value(newAutoId),
                autoCategorySource: Value(newSource),
                autoCategoryConfidence: Value(newConfidence),
              ),
            );
            changed++;
          }
        }
      });
    }

    return changed;
  }
}

final autoCategoriserProvider = Provider<AutoCategoriser>(
  (ref) => AutoCategoriser(ref.watch(appDatabaseProvider)),
);
