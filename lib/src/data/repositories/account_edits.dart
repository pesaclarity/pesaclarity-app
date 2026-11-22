import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'message_reads_repository.dart';
import 'sacco_links.dart';
import 'savings_links.dart';

/// Editing and removing one of the person's accounts (Profile › My
/// accounts › an account). Every change keeps balances, the journal, own
/// transfers, loans, goals, money between spaces and Firefly III right:
/// the journal and the Firefly III outbox follow the transactions through
/// the database's own triggers.
class AccountEdits {
  AccountEdits(this._db);

  final AppDatabase _db;

  /// How many transactions [accountId] has.
  Future<int> transactionCount(int accountId) async {
    final t = _db.transactions;
    final count = t.id.count();
    final row =
        await (_db.selectOnly(t)
              ..addColumns([count])
              ..where(t.accountId.equals(accountId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// How many transactions [accountId] has, and the first and last day.
  Future<({int count, DateTime? first, DateTime? last})> stats(
    int accountId,
  ) async {
    final t = _db.transactions;
    final count = t.id.count();
    final first = t.occurredAt.min();
    final last = t.occurredAt.max();
    final row =
        await (_db.selectOnly(t)
              ..addColumns([count, first, last])
              ..where(t.accountId.equals(accountId)))
            .getSingle();
    return (
      count: row.read(count) ?? 0,
      first: row.read(first),
      last: row.read(last),
    );
  }

  /// Saves what the account page changed. Null leaves a field as it is;
  /// [countsOnHand] is always written (null follows the type).
  Future<void> save(
    int accountId, {
    String? name,
    AccountType? type,
    String? lastDigits,
    bool? hidden,
    bool? countsOnHand,
    bool setCountsOnHand = false,
  }) => _db.transaction(() async {
    final account = await _account(accountId);
    final fromMessages = account.institutionId != null;
    final digits = lastDigits?.replaceAll(RegExp(r'\D'), '');
    await (_db.update(
      _db.accounts,
    )..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(
        name: name == null || name.trim().isEmpty
            ? const Value.absent()
            : Value(name.trim()),
        // Its messages say what it is.
        type: type == null || fromMessages ? const Value.absent() : Value(type),
        reference: lastDigits == null || fromMessages
            ? const Value.absent()
            : Value(digits!.isEmpty ? null : '***$digits'),
        hidden: hidden == null ? const Value.absent() : Value(hidden),
        countsOnHand: setCountsOnHand
            ? Value(countsOnHand)
            : const Value.absent(),
      ),
    );
    if (type == AccountType.sacco && !fromMessages) {
      await _db
          .into(_db.saccoDetails)
          .insert(
            SaccoDetailsCompanion.insert(accountId: Value(accountId)),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });

  /// Removes [accountId] and its [transactionIds]-or-all transactions: the
  /// messages behind them are set aside so reading messages again never
  /// brings them back, their other sides count as they were, and what the
  /// app wrote for them on savings accounts and SACCOs goes too.
  Future<void> delete(int accountId) => _db.transaction(() async {
    final account = await _account(accountId);
    if (account.institutionId != null) {
      throw StateError('An account read from messages is not removed.');
    }
    final t = _db.transactions;
    final ids =
        await (_db.selectOnly(t)
              ..addColumns([t.id])
              ..where(t.accountId.equals(accountId)))
            .map((r) => r.read(t.id)!)
            .get();
    await _removeTransactions(ids);
    await _letGo(accountId);
    await (_db.delete(_db.accounts)..where((a) => a.id.equals(accountId))).go();
    await syncSavingsAccounts(_db);
    await syncSaccos(_db);
  });

  /// Moves every transaction of [fromId] to [toId], then removes [fromId].
  /// The two must count in the same currency. Own transfers between the
  /// two would move money from an account to itself, and a transaction
  /// [toId] has already (same dedupe key) is a copy: both go, their
  /// messages set aside. Money said to have moved to or from [fromId] now
  /// names [toId]; its balance records (money between spaces), statements
  /// and repeats follow.
  Future<void> moveAndRemove(int fromId, int toId) => _db.transaction(() async {
    if (fromId == toId) throw ArgumentError('Same account');
    final from = await _account(fromId);
    final to = await _account(toId);
    if (from.institutionId != null) {
      throw StateError('An account read from messages is not removed.');
    }
    if (from.currency != to.currency) {
      throw ArgumentError('Accounts count in different currencies');
    }
    final t = _db.transactions;
    final moving = await (_db.select(
      t,
    )..where((t) => t.accountId.equals(fromId))).get();
    final keys = {
      for (final r
          in await (_db.select(t)..where(
                (t) => t.accountId.equals(toId) & t.dedupeKey.isNotNull(),
              ))
              .get())
        r.dedupeKey!,
    };
    final drop = <int>{};
    for (final r in moving) {
      if (r.dedupeKey != null && keys.contains(r.dedupeKey)) drop.add(r.id);
      final pair = r.transferPairId;
      if (pair != null) {
        final other = await (_db.select(
          t,
        )..where((t) => t.id.equals(pair))).getSingleOrNull();
        if (other != null && other.accountId == toId) {
          drop
            ..add(r.id)
            ..add(other.id);
        }
      }
    }
    await _removeTransactions(drop.toList());
    await (_db.update(t)..where(
          (t) => t.transferAccountId.equals(fromId) & t.accountId.equals(toId),
        ))
        .write(const TransactionsCompanion(transferAccountId: Value(null)));
    await (_db.update(t)..where(
          (t) => t.transferAccountId.equals(toId) & t.accountId.equals(fromId),
        ))
        .write(const TransactionsCompanion(transferAccountId: Value(null)));
    await (_db.update(t)..where((t) => t.transferAccountId.equals(fromId)))
        .write(TransactionsCompanion(transferAccountId: Value(toId)));
    await (_db.update(t)..where((t) => t.accountId.equals(fromId))).write(
      TransactionsCompanion(accountId: Value(toId)),
    );
    await (_db.update(_db.balanceRecords)
          ..where((b) => b.accountId.equals(fromId)))
        .write(BalanceRecordsCompanion(accountId: Value(toId)));
    await (_db.update(_db.imports)..where((i) => i.accountId.equals(fromId)))
        .write(ImportsCompanion(accountId: Value(toId)));
    await (_db.update(_db.recurring)..where((r) => r.accountId.equals(fromId)))
        .write(RecurringCompanion(accountId: Value(toId)));
    await _db.customStatement(
      'INSERT OR IGNORE INTO moved_transactions (account_id, dedupe_key, '
      'space_id) SELECT ?, dedupe_key, space_id FROM moved_transactions '
      'WHERE account_id = ?',
      [toId, fromId],
    );
    await (_db.update(_db.accounts)
          ..where((a) => a.linkedAccountId.equals(fromId)))
        .write(AccountsCompanion(linkedAccountId: Value(toId)));
    await _letGo(fromId);
    await (_db.delete(_db.accounts)..where((a) => a.id.equals(fromId))).go();
    await syncSavingsAccounts(_db);
    await syncSaccos(_db);
  });

  /// Removes transactions [ids] the way clearing records does.
  Future<void> _removeTransactions(List<int> ids) async {
    if (ids.isEmpty) return;
    final t = _db.transactions;
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      await setAsideMessagesOf(_db, chunk);
      // What the app wrote for these on a SACCO goes with them.
      await (_db.delete(t)..where(
            (t) => t.dedupeKey.isIn([
              for (final id in chunk) ...[
                saccoDepositKey(id),
                saccoLoanKey(id),
              ],
            ]),
          ))
          .go();
      // Mirrors on savings accounts the app keeps go with their payment.
      final mirrors =
          await (_db.selectOnly(t)
                ..addColumns([t.id])
                ..where(
                  t.transferPairId.isIn(chunk) &
                      t.id.isInQuery(
                        _db.selectOnly(_db.savingsEntries)
                          ..addColumns([_db.savingsEntries.transactionId]),
                      ) &
                      t.source.equalsValue(TransactionSource.manual),
                ))
              .map((r) => r.read(t.id)!)
              .get();
      await (_db.update(t)..where(
            (t) =>
                t.transferPairId.isIn(chunk) | t.transferPairId.isIn(mirrors),
          ))
          .write(const TransactionsCompanion(transferPairId: Value(null)));
      await (_db.delete(t)..where((t) => t.id.isIn(mirrors))).go();
      await (_db.delete(t)..where((t) => t.id.isIn(chunk))).go();
    }
  }

  /// What still names [accountId] lets go of it before it is removed.
  Future<void> _letGo(int accountId) async {
    final t = _db.transactions;
    await (_db.update(t)..where((t) => t.transferAccountId.equals(accountId)))
        .write(const TransactionsCompanion(transferAccountId: Value(null)));
    await (_db.update(_db.recurring)
          ..where((r) => r.accountId.equals(accountId)))
        .write(const RecurringCompanion(accountId: Value(null)));
    await (_db.delete(
      _db.imports,
    )..where((i) => i.accountId.equals(accountId))).go();
    await (_db.update(_db.accounts)..where((a) => a.familyOf.equals(accountId)))
        .write(const AccountsCompanion(familyOf: Value(null)));
    await (_db.update(_db.accounts)
          ..where((a) => a.linkedAccountId.equals(accountId)))
        .write(const AccountsCompanion(linkedAccountId: Value(null)));
  }

  Future<Account> _account(int id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id))).getSingle();
}

final accountEditsProvider = Provider<AccountEdits>(
  (ref) => AccountEdits(ref.watch(appDatabaseProvider)),
);
