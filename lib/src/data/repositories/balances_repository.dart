import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Corrections and fixes that keep each account's balance true. Payments
/// themselves are never edited: a correction is its own visible entry, a
/// copy is removed whole, a payment is moved whole.
abstract interface class BalancesRepository {
  /// Records that [accountId] really holds [statedMinor] at [at]: a
  /// "Balance correction" for [differenceMinor] (what it holds less what
  /// the app showed), which becomes the account's new checkpoint. For
  /// M-Pesa, [statedMinor] is the wallet less any Fuliza owed, so it may be
  /// below zero. Returns the correction's id.
  Future<int> setBalance(
    int accountId, {
    required int statedMinor,
    required int differenceMinor,
    required DateTime at,
    required String currency,
  });

  /// Records a correction of [differenceMinor] at [at] on [accountId] that
  /// explains a gap between two reported balances. It is not a checkpoint.
  Future<int> addGapCorrection(
    int accountId, {
    required int differenceMinor,
    required DateTime at,
    required String currency,
  });

  /// Removes correction [id]. Only corrections can be undone this way.
  Future<void> undoCorrection(int id);

  /// Removes [copyId], a duplicate of [keptId]: links to the copy (sales,
  /// quick records, tags) move to the one kept.
  Future<void> removeCopy(int copyId, {required int keptId});

  /// Moves transaction [id] to [accountId], whole.
  Future<void> moveToAccount(int id, int accountId);

  /// Adds an account without messages, such as cash, holding [balanceMinor]
  /// from [at]. Returns its id.
  Future<int> addAccount({
    required String name,
    required AccountType type,
    required String currency,
    required int balanceMinor,
    required DateTime at,
  });
}

class DriftBalancesRepository implements BalancesRepository {
  DriftBalancesRepository(this._db);

  final AppDatabase _db;

  TransactionsCompanion _correction(
    int accountId, {
    required int differenceMinor,
    required DateTime at,
    required String currency,
    int? statedMinor,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: differenceMinor.abs(),
    direction: differenceMinor < 0
        ? TransactionDirection.outflow
        : TransactionDirection.inflow,
    kind: const Value(TransactionKind.correction),
    currency: Value(currency),
    source: TransactionSource.manual,
    balanceAfterMinor: Value(statedMinor),
  );

  @override
  Future<int> setBalance(
    int accountId, {
    required int statedMinor,
    required int differenceMinor,
    required DateTime at,
    required String currency,
  }) => _db
      .into(_db.transactions)
      .insert(
        _correction(
          accountId,
          differenceMinor: differenceMinor,
          at: at,
          currency: currency,
          statedMinor: statedMinor,
        ),
      );

  @override
  Future<int> addGapCorrection(
    int accountId, {
    required int differenceMinor,
    required DateTime at,
    required String currency,
  }) => _db
      .into(_db.transactions)
      .insert(
        _correction(
          accountId,
          differenceMinor: differenceMinor,
          at: at,
          currency: currency,
        ),
      );

  @override
  Future<void> undoCorrection(int id) =>
      (_db.delete(_db.transactions)..where(
            (t) =>
                t.id.equals(id) &
                t.kind.equalsValue(TransactionKind.correction),
          ))
          .go();

  @override
  Future<void> removeCopy(int copyId, {required int keptId}) =>
      _db.transaction(() async {
        for (final table in ['sale_payments', 'quick_records']) {
          await _db.customStatement(
            'UPDATE $table SET transaction_id = ? WHERE transaction_id = ?',
            [keptId, copyId],
          );
        }
        await _db.customStatement(
          'INSERT OR IGNORE INTO transaction_tags (transaction_id, tag_id) '
          'SELECT ?, tag_id FROM transaction_tags WHERE transaction_id = ?',
          [keptId, copyId],
        );
        await (_db.update(_db.transactions)
              ..where((t) => t.transferPairId.equals(copyId)))
            .write(const TransactionsCompanion(transferPairId: Value(null)));
        await (_db.delete(
          _db.transactions,
        )..where((t) => t.id.equals(copyId))).go();
      });

  @override
  Future<void> moveToAccount(int id, int accountId) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(accountId: Value(accountId)),
      );

  @override
  Future<int> addAccount({
    required String name,
    required AccountType type,
    required String currency,
    required int balanceMinor,
    required DateTime at,
  }) => _db
      .into(_db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          currency: Value(currency),
          openingBalanceMinor: Value(balanceMinor),
          openingDate: at,
        ),
      );
}

final balancesRepositoryProvider = Provider<BalancesRepository>(
  (ref) => DriftBalancesRepository(ref.watch(appDatabaseProvider)),
);
