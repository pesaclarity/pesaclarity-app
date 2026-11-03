import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/spaces/space.dart';
import '../database/app_database.dart';
import '../database/connection.dart';
import '../database/database_providers.dart';

/// Moves a transaction from the open space to another, such as a sale on a
/// shared M-Pesa line that belongs to the business.
abstract interface class SpaceMoveRepository {
  /// Moves [transactionId] to [spaceId]. Its account comes along by
  /// institution or name; its category comes along when the other space has
  /// one with the same key. The open space remembers the move, so reading
  /// the same message again does not bring it back.
  Future<void> move(int transactionId, String spaceId);
}

class DriftSpaceMoveRepository implements SpaceMoveRepository {
  DriftSpaceMoveRepository(this._source, this._openTarget);

  final AppDatabase _source;

  /// Opens [spaceId]'s database and says whether the caller must close it.
  final Future<(AppDatabase, bool)> Function(String spaceId) _openTarget;

  @override
  Future<void> move(int transactionId, String spaceId) async {
    final tx = await (_source.select(
      _source.transactions,
    )..where((t) => t.id.equals(transactionId))).getSingle();
    final account = await (_source.select(
      _source.accounts,
    )..where((a) => a.id.equals(tx.accountId))).getSingle();
    final categoryId = tx.categoryOverrideId ?? tx.autoCategoryId;
    final category = categoryId == null
        ? null
        : await (_source.select(
            _source.categories,
          )..where((c) => c.id.equals(categoryId))).getSingleOrNull();

    final (target, close) = await _openTarget(spaceId);
    try {
      await target.transaction(() async {
        final accountId = await _accountIn(target, account, tx.occurredAt);
        final targetCategory = category?.key == null
            ? null
            : await (target.select(
                target.categories,
              )..where((c) => c.key.equals(category!.key!))).getSingleOrNull();
        final key = tx.dedupeKey;
        if (key != null &&
            await (target.select(target.transactions)..where(
                      (t) =>
                          t.accountId.equals(accountId) &
                          t.dedupeKey.equals(key),
                    ))
                    .getSingleOrNull() !=
                null) {
          return;
        }
        await target
            .into(target.transactions)
            .insert(
              tx
                  .toCompanion(false)
                  .copyWith(
                    id: const Value.absent(),
                    accountId: Value(accountId),
                    payeeId: const Value(null),
                    transferPairId: const Value(null),
                    categoryOverrideId: Value(targetCategory?.id),
                    autoCategoryId: const Value(null),
                    autoCategorySource: const Value(null),
                    autoCategoryConfidence: const Value(null),
                  ),
            );
        // Moving back undoes an earlier move away.
        if (key != null) {
          await (target.delete(target.movedTransactions)..where(
                (m) => m.accountId.equals(accountId) & m.dedupeKey.equals(key),
              ))
              .go();
        }
      });
    } finally {
      if (close) await target.close();
    }

    await _source.transaction(() async {
      final key = tx.dedupeKey;
      if (key != null) {
        await _source
            .into(_source.movedTransactions)
            .insertOnConflictUpdate(
              MovedTransactionsCompanion.insert(
                accountId: tx.accountId,
                dedupeKey: key,
                spaceId: spaceId,
              ),
            );
      }
      await (_source.delete(
        _source.transactions,
      )..where((t) => t.id.equals(transactionId))).go();
    });
  }

  /// The account in [db] that matches [account]: the same institution, else
  /// the same name and type, else a new one with no opening balance.
  Future<int> _accountIn(
    AppDatabase db,
    Account account,
    DateTime firstSeen,
  ) async {
    final institution = account.institutionId;
    final existing =
        await (db.select(db.accounts)..where(
              (a) => institution != null
                  ? a.institutionId.equals(institution)
                  : a.name.equals(account.name) &
                        a.type.equalsValue(account.type),
            ))
            .get();
    if (existing.isNotEmpty) return existing.first.id;
    return db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: account.name,
            type: account.type,
            currency: Value(account.currency),
            openingDate: firstSeen,
            institutionId: Value(institution),
          ),
        );
  }
}

final spaceMoveRepositoryProvider = Provider<SpaceMoveRepository>((ref) {
  final source = ref.watch(appDatabaseProvider);
  return DriftSpaceMoveRepository(source, (spaceId) async {
    if (spaceId == personalSpaceId) {
      return (ref.read(personalDatabaseProvider), false);
    }
    final db = openEncryptedDatabase(
      ref.read(databaseKeyStoreProvider),
      beforeOpen: ref.read(databaseFileLockProvider).waitUntilFree,
      spaceId: spaceId,
    );
    return (db, true);
  });
});
