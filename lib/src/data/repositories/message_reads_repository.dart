import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// A transaction already read from a message, and whether the person has
/// made it theirs since (see [MessageReadsRepository.stored]).
class StoredReading {
  const StoredReading(this.record, {required this.touched});

  final TransactionRecord record;

  /// The person changed or added something on it, so reading its message
  /// again leaves it as it is.
  final bool touched;
}

/// What is already known about messages, by their hash, so reading them
/// again never stores one twice or undoes what the person decided.
class MessageReadsRepository {
  MessageReadsRepository(this._db);

  final AppDatabase _db;

  /// SQLite caps the number of values in one query.
  static const _chunk = 500;

  /// Transactions already read from the messages [hashes], by hash.
  ///
  /// One counts as touched when the person has given it anything of their
  /// own: a category, a named payee, a note, a goal or debt, an own-account
  /// link or transfer pair, a rate, tags, a sale or record, an eTIMS
  /// invoice, a category they confirmed, or when it came from a message
  /// they checked themselves.
  Future<Map<String, StoredReading>> stored(Set<String> hashes) async {
    final rows = <TransactionRecord>[];
    for (final chunk in _chunks(hashes)) {
      rows.addAll(
        await (_db.select(
          _db.transactions,
        )..where((t) => t.messageHash.isIn(chunk))).get(),
      );
    }
    if (rows.isEmpty) return const {};
    final linked = await _linked({for (final r in rows) r.id});
    final checked = await _checked({for (final r in rows) r.messageHash!});
    return {
      for (final r in rows)
        r.messageHash!: StoredReading(
          r,
          touched:
              linked.contains(r.id) ||
              // Read by the readers after the person left it in review.
              (checked.contains(r.messageHash) && r.readBy == null) ||
              r.categoryOverrideId != null ||
              r.payeeId != null ||
              r.item != null ||
              r.goalId != null ||
              r.debtId != null ||
              r.transferAccountId != null ||
              r.transferPairId != null ||
              r.fxRateMicros != null,
        ),
    };
  }

  /// Review items for the messages [hashes], by hash: true once the person
  /// dealt with it.
  Future<Map<String, (int, bool)>> reviewItems(Set<String> hashes) async {
    final found = <String, (int, bool)>{};
    for (final chunk in _chunks(hashes)) {
      for (final item in await (_db.select(
        _db.reviewItems,
      )..where((r) => r.messageHash.isIn(chunk))).get()) {
        found[item.messageHash] = (item.id, item.resolvedAt != null);
      }
    }
    return found;
  }

  /// Which of [hashes] the person set aside (see [SetAsideMessages]).
  Future<Set<String>> setAside(Set<String> hashes) async {
    final found = <String>{};
    for (final chunk in _chunks(hashes)) {
      found.addAll(
        await (_db.select(_db.setAsideMessages)
              ..where((m) => m.messageHash.isIn(chunk)))
            .map((m) => m.messageHash)
            .get(),
      );
    }
    return found;
  }

  /// Writes [fresh]'s reader fields over [row], read by [readBy]. Returns
  /// false, changing nothing, when [fresh]'s dedupe key belongs to another
  /// transaction in the account: it would then be a copy of that one.
  Future<bool> update(
    TransactionRecord row,
    TransactionsCompanion fresh, {
    required String readBy,
  }) => _db.transaction(() async {
    final key = fresh.dedupeKey.value;
    if (key != null && key != row.dedupeKey) {
      final other =
          await (_db.selectOnly(_db.transactions)
                ..addColumns([_db.transactions.id])
                ..where(
                  _db.transactions.accountId.equals(row.accountId) &
                      _db.transactions.dedupeKey.equals(key),
                )
                ..limit(1))
              .getSingleOrNull();
      if (other != null) return false;
    }
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(row.id))).write(
      TransactionsCompanion(
        occurredAt: fresh.occurredAt,
        amountMinor: fresh.amountMinor,
        direction: fresh.direction,
        kind: fresh.kind,
        feeMinor: fresh.feeMinor,
        counterpartyKind: fresh.counterpartyKind,
        counterpartyValue: fresh.counterpartyValue,
        counterpartyName: fresh.counterpartyName,
        receiptNo: fresh.receiptNo,
        dedupeKey: fresh.dedupeKey,
        balanceAfterMinor: fresh.balanceAfterMinor,
        owedAfterMinor: fresh.owedAfterMinor,
        owedDueAt: fresh.owedDueAt,
        readBy: Value(readBy),
      ),
    );
    return true;
  });

  /// Notes that [readBy] read transaction [id] and found nothing to change.
  Future<void> stamp(int id, String readBy) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(readBy: Value(readBy)),
      );

  /// Whether any transaction from a message was read before the readers
  /// were noted on it.
  Future<bool> hasUnnotedReads() async =>
      await (_db.selectOnly(_db.transactions)
            ..addColumns([_db.transactions.id])
            ..where(
              _db.transactions.messageHash.isNotNull() &
                  _db.transactions.source.equalsValue(TransactionSource.sms) &
                  _db.transactions.kind.isNotNull() &
                  _db.transactions.readBy.isNull(),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Transactions linked from the person's own records.
  Future<Set<int>> _linked(Set<int> ids) async {
    final found = <int>{};
    final list = ids.toList();
    for (var i = 0; i < list.length; i += _chunk) {
      final chunk = list.sublist(i, _end(i, list.length));
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final table in [
        'transaction_tags',
        'sale_payments',
        'quick_records',
        'etims_costs',
        'category_confirmations',
      ]) {
        found.addAll(
          await _db
              .customSelect(
                'SELECT DISTINCT transaction_id AS id FROM $table '
                'WHERE transaction_id IN ($marks)',
                variables: [for (final id in chunk) Variable.withInt(id)],
              )
              .map((row) => row.read<int>('id'))
              .get(),
        );
      }
    }
    return found;
  }

  /// Messages the person checked themselves in review.
  Future<Set<String>> _checked(Set<String> hashes) async =>
      (await reviewItems(hashes)).keys.toSet();

  static Iterable<List<String>> _chunks(Set<String> values) sync* {
    final list = values.toList();
    for (var i = 0; i < list.length; i += _chunk) {
      yield list.sublist(i, _end(i, list.length));
    }
  }

  static int _end(int i, int length) =>
      i + _chunk > length ? length : i + _chunk;
}

/// Sets aside the messages behind [transactionIds] in [db], before they are
/// removed, so reading the messages again never brings them back: each
/// one's own message and, for two messages kept as one transaction, the
/// second message merged into it.
Future<void> setAsideMessagesOf(
  AppDatabase db,
  Iterable<int> transactionIds,
) async {
  final ids = transactionIds.toList();
  final t = db.transactions;
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    final rows =
        await (db.selectOnly(t)
              ..addColumns([t.messageHash, t.twinMessageHash])
              ..where(
                t.id.isIn(chunk) &
                    (t.messageHash.isNotNull() | t.twinMessageHash.isNotNull()),
              ))
            .get();
    final hashes = {
      for (final row in rows) ...[
        ?row.read(t.messageHash),
        ?row.read(t.twinMessageHash),
      ],
    };
    for (final hash in hashes) {
      await db
          .into(db.setAsideMessages)
          .insertOnConflictUpdate(
            SetAsideMessagesCompanion.insert(messageHash: hash),
          );
    }
  }
}

final messageReadsRepositoryProvider = Provider<MessageReadsRepository>(
  (ref) => MessageReadsRepository(ref.watch(appDatabaseProvider)),
);
