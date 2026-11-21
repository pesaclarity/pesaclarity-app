import 'package:drift/drift.dart';

import '../../domain/categories/default_categories.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/own_transfers.dart';
import '../../domain/savings/savings_pockets.dart';
import '../../domain/savings/savings_product.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import 'category_seeds.dart';

// Savings accounts the app keeps (an account with a `product`, such as
// Chumz) have no messages of their own. Every payment into one stays on the
// account it was paid from, as its message has it, and gets a mirror entry
// on the savings account, paired with it as an own transfer: money out of
// M-Pesa, money into Chumz, counted once and never as spending. The
// functions here keep the mirrors in step with the payments, and work out
// interest from the balances the person types.

/// What bringing savings accounts in step with the payments did.
class SavingsSync {
  const SavingsSync({
    this.linked = const {},
    this.refreshed = 0,
    this.removed = 0,
    this.skipped = 0,
  });

  /// Payments and money back newly counted as transfers, by transaction id.
  final Set<int> linked;

  /// Mirror entries brought back in line with a payment that changed.
  final int refreshed;

  /// Mirror entries removed: their payment is gone, or no longer the
  /// product's.
  final int removed;

  /// Payments that name the product but were left as they are: in another
  /// currency than the account, or matched by hand to another account.
  final int skipped;

  bool get changed => linked.isNotEmpty || refreshed > 0 || removed > 0;

  SavingsSync operator +(SavingsSync other) => SavingsSync(
    linked: {...linked, ...other.linked},
    refreshed: refreshed + other.refreshed,
    removed: removed + other.removed,
    skipped: skipped + other.skipped,
  );
}

/// A payment that names a savings product, as [findSavingsPayments] reads
/// it.
class SavingsPayment {
  const SavingsPayment(this.record, this.move, {required this.skipped});

  final TransactionRecord record;
  final SavingsMove move;

  /// Whether adding the product would leave it as it is (see
  /// [SavingsSync.skipped]).
  final bool skipped;
}

/// Whether transaction [id] is an entry on a savings account the app keeps,
/// or the payment such an entry mirrors. These are kept in step by the app:
/// they are not unmatched, moved to another account or to another space.
Future<bool> isSavingsLinked(AppDatabase db, int id) async {
  final rows = await db
      .customSelect(
        'SELECT 1 FROM savings_entries e WHERE e.transaction_id = ?1 '
        'OR e.transaction_id = '
        '(SELECT transfer_pair_id FROM transactions WHERE id = ?1) LIMIT 1',
        variables: [Variable.withInt(id)],
        readsFrom: {db.savingsEntries, db.transactions},
      )
      .get();
  return rows.isNotEmpty;
}

/// Whether transaction [id] is itself an entry on a savings account the app
/// keeps.
Future<bool> isSavingsEntry(AppDatabase db, int id) async =>
    await (db.select(
      db.savingsEntries,
    )..where((e) => e.transactionId.equals(id))).getSingleOrNull() !=
    null;

/// Links the new or changed transactions [transactionIds] to the savings
/// accounts the app keeps: a payment to a product's paybill, or money it
/// paid back, gets its mirror entry at once, and so does money the person
/// said moved to or from such an account. A transaction typed on a savings
/// account itself joins its entries.
///
/// Its first query asks whether any account is a savings product, so with
/// none this costs one small query.
Future<SavingsSync> linkSavingsPayments(
  AppDatabase db,
  Iterable<int> transactionIds, {
  List<SavingsProduct> products = savingsProducts,
}) => db.transaction(() async {
  final kept = await _keptAccounts(db, products);
  if (kept.isEmpty) return const SavingsSync();
  final rows = await _rowsById(db, transactionIds);
  final partners = await _rowsById(db, [
    for (final r in rows.values) ?r.transferPairId,
  ]);
  var done = const SavingsSync();
  for (final account in kept) {
    final id = account.account.id;
    // On the account, naming it or its product, or matched with an entry
    // on it: a payment that stopped being the account's loses its mirror.
    final mine = [
      for (final r in rows.values)
        if (r.accountId == id ||
            account.concerns(r) ||
            partners[r.transferPairId]?.accountId == id)
          r,
    ];
    if (mine.isEmpty) continue;
    done += await _sync(db, account, only: mine);
  }
  return done;
});

/// Brings the savings accounts the app keeps (or only [accountId]) in step
/// with the payments, in one database transaction. Safe to run at any time:
/// run again, it changes nothing.
///
/// For each account it finds every payment to its product and all money
/// back from it, makes a pocket for each account code, writes the mirror
/// entries that are missing and brings those of a changed payment back in
/// line, removes mirrors whose payment is gone or is no longer the
/// product's, moves the account's opening date back to its first entry, and
/// works out interest again from the typed balances.
///
/// A payment that pairing had matched with an unrelated transaction is
/// unmatched (and the pair remembered, so pairing does not make it again)
/// and linked; one the person matched by hand or said went to another
/// account, and one in another currency than the account, is left alone and
/// counted as skipped.
Future<SavingsSync> syncSavingsAccounts(
  AppDatabase db, {
  int? accountId,
  List<SavingsProduct> products = savingsProducts,
}) => db.transaction(() async {
  var done = const SavingsSync();
  for (final account in await _keptAccounts(db, products)) {
    if (accountId != null && account.account.id != accountId) continue;
    done += await _sync(db, account);
  }
  return done;
});

/// The payments on the person's accounts that name [product]: what adding
/// it would link, and what it would skip. Oldest first.
Future<List<SavingsPayment>> findSavingsPayments(
  AppDatabase db,
  SavingsProduct product,
) async {
  final kept = {
    for (final a in await (db.select(
      db.accounts,
    )..where((a) => a.product.isNotNull())).get())
      a.id,
  };
  final rows = [
    for (final r in await _named(db, product).get())
      if (!kept.contains(r.accountId)) r,
  ];
  final partners = await _rowsById(db, [
    for (final r in rows) ?r.transferPairId,
  ]);
  return [
    for (final r in rows)
      if (_moveOf(r, product) case final move?)
        SavingsPayment(
          r,
          move,
          skipped:
              r.currency != product.currency ||
              r.transferAccountId != null ||
              (partners[r.transferPairId] != null &&
                  _pairedByHand(r, partners[r.transferPairId]!)),
        ),
  ];
}

/// Removes the typed balances in `[from, to)` after the records of that
/// range were cleared, then brings every savings account back in step: the
/// entries of the range went with its transactions.
Future<void> clearSavingsRange(AppDatabase db, DateTime from, DateTime to) =>
    db.transaction(() async {
      await (db.delete(db.savingsReadings)..where(
            (r) =>
                r.at.isBiggerOrEqualValue(from) & r.at.isSmallerThanValue(to),
          ))
          .go();
      await syncSavingsAccounts(db);
    });

/// Undoes the update of [accountId]'s balances typed at [at]: the balances
/// go, and with them the interest and correction they showed.
Future<void> undoSavingsUpdate(AppDatabase db, int accountId, DateTime at) =>
    db.transaction(() async {
      final second = wholeSecond(at);
      await (db.delete(db.savingsReadings)..where(
            (r) =>
                r.at.isBiggerOrEqualValue(second) &
                r.at.isSmallerThanValue(
                  second.add(const Duration(seconds: 1)),
                ) &
                r.pocketId.isInQuery(
                  db.selectOnly(db.savingsPockets)
                    ..addColumns([db.savingsPockets.id])
                    ..where(db.savingsPockets.accountId.equals(accountId)),
                ),
          ))
          .go();
      await settleSavingsReadings(db, accountId);
    });

/// [at] to the second, as the database keeps times.
DateTime wholeSecond(DateTime at) => DateTime.fromMillisecondsSinceEpoch(
  at.millisecondsSinceEpoch ~/ 1000 * 1000,
  isUtc: true,
);

/// Works out [accountId]'s interest and corrections again from its pockets'
/// typed balances and the money in and out (see [settleAccount]). For each
/// time balances were typed it keeps at most one interest entry, income
/// under the Interest category, and one correction, which is never income
/// or spending; it changes their amounts when older payments turn up, and
/// removes them when their balances are gone.
Future<void> settleSavingsReadings(
  AppDatabase db,
  int accountId, {
  List<SavingsProduct> products = savingsProducts,
}) => db.transaction(() async {
  final account = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(accountId))).getSingleOrNull();
  if (account == null || account.product == null) return;
  await _settle(
    db,
    _Kept(account, savingsProductById(account.product, products: products)),
  );
});

/// A savings account the app keeps, with the product it is when this app
/// knows it.
class _Kept {
  _Kept(this.account, this.product);

  final Account account;
  final SavingsProduct? product;

  /// What [row], on another account, is to this one's product.
  SavingsMove? moveOf(TransactionRecord row) =>
      product == null ? null : _moveOf(row, product!);

  /// Whether [row], on another account, may belong here: it names the
  /// product, or the person said it moved to or from this account.
  bool concerns(TransactionRecord row) =>
      row.accountId != account.id &&
      (row.transferAccountId == account.id || moveOf(row) != null);
}

SavingsMove? _moveOf(TransactionRecord row, SavingsProduct product) =>
    savingsMoveOf(
      kind: row.kind,
      direction: row.direction,
      counterpartyKind: row.counterpartyKind,
      counterpartyValue: row.counterpartyValue,
      counterpartyName: row.counterpartyName,
      products: [product],
    );

Future<List<_Kept>> _keptAccounts(
  AppDatabase db,
  List<SavingsProduct> products,
) async => [
  for (final a
      in await (db.select(db.accounts)
            ..where((a) => a.product.isNotNull())
            ..orderBy([(a) => OrderingTerm.asc(a.id)]))
          .get())
    _Kept(a, savingsProductById(a.product, products: products)),
];

Future<Map<int, TransactionRecord>> _rowsById(
  AppDatabase db,
  Iterable<int> ids,
) async {
  final list = ids.toSet().toList();
  final found = <int, TransactionRecord>{};
  // SQLite caps the number of values in one query.
  for (var i = 0; i < list.length; i += 500) {
    final chunk = list.sublist(
      i,
      i + 500 > list.length ? list.length : i + 500,
    );
    for (final r in await (db.select(
      db.transactions,
    )..where((t) => t.id.isIn(chunk))).get()) {
      found[r.id] = r;
    }
  }
  return found;
}

/// Transactions whose printed name may be [product]'s, oldest first: a
/// loose match in the database, which [savingsMoveOf] then decides.
SimpleSelectStatement<$TransactionsTable, TransactionRecord> _named(
  AppDatabase db,
  SavingsProduct product,
) {
  final words = {
    for (final name in [...product.payeeNames, ...?product.moneyBackNames])
      name.split(' ').first,
  };
  return db.select(db.transactions)
    ..where((t) {
      Expression<bool> names = const Constant(false);
      for (final word in words) {
        names =
            names |
            t.counterpartyName.like('%$word%') |
            t.counterpartyValue.like('%$word%');
      }
      return names &
          ((t.kind.equalsValue(TransactionKind.paybill) &
                  t.direction.equalsValue(TransactionDirection.outflow)) |
              (t.kind.equalsValue(TransactionKind.received) &
                  t.direction.equalsValue(TransactionDirection.inflow)));
    })
    ..orderBy([
      (t) => OrderingTerm.asc(t.occurredAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
}

/// Whether the pair [row] and [partner] is one the person made: either side
/// names its other account, was typed by hand, or the two are not a pair
/// that pairing makes by itself (see `findOwnTransfers`).
bool _pairedByHand(TransactionRecord row, TransactionRecord partner) {
  if (row.transferAccountId != null || partner.transferAccountId != null) {
    return true;
  }
  if (row.source == TransactionSource.manual ||
      partner.source == TransactionSource.manual ||
      row.direction == partner.direction) {
    return true;
  }
  if (row.occurredAt.difference(partner.occurredAt).abs() >
      defaultTransferWindow) {
    return true;
  }
  final out = row.direction == TransactionDirection.outflow ? row : partner;
  final into = identical(out, row) ? partner : row;
  LedgerEntry entry(TransactionRecord r) => LedgerEntry(
    id: r.id,
    accountId: r.accountId,
    occurredAt: r.occurredAt,
    amountMinor: r.amountMinor,
    direction: r.direction,
    kind: r.kind ?? TransactionKind.bank,
    currency: r.currency,
    feeMinor: r.feeMinor,
  );
  final fit = transferFit(entry(out), entry(into));
  return fit == null || fit == TransferFit.loose;
}

bool _sameSecond(DateTime a, DateTime b) =>
    a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;

/// An entry on a savings account: its transaction and its record.
typedef SavingsEntryRecord = ({TransactionRecord row, SavingsEntryRow entry});

/// The entries on savings account [accountId], oldest first.
Future<List<SavingsEntryRecord>> savingsEntriesOf(
  AppDatabase db,
  int accountId,
) async {
  final t = db.transactions;
  final e = db.savingsEntries;
  final rows =
      await (db.select(t).join([innerJoin(e, e.transactionId.equalsExp(t.id))])
            ..where(t.accountId.equals(accountId))
            ..orderBy([OrderingTerm.asc(t.occurredAt), OrderingTerm.asc(t.id)]))
          .get();
  return [for (final r in rows) (row: r.readTable(t), entry: r.readTable(e))];
}

/// Whether an entry is a mirror the app wrote: money in or out that names
/// the account its other side is on. Money the person typed on the savings
/// account names none.
bool isSavingsMirror(SavingsEntryRecord e) =>
    (e.entry.kind == SavingsEntryKind.paidIn ||
        e.entry.kind == SavingsEntryKind.takenOut) &&
    e.row.transferAccountId != null;

/// Brings [kept] in step with the payments: every one, or [only] those,
/// which may also be transactions on the account itself.
Future<SavingsSync> _sync(
  AppDatabase db,
  _Kept kept, {
  List<TransactionRecord>? only,
}) async {
  final account = kept.account;
  final t = db.transactions;
  var pockets = await savingsPocketsOf(db, account.id);

  // The payments to look at, oldest first.
  final List<TransactionRecord> candidates;
  if (only != null) {
    candidates = [
      for (final r in only)
        if (r.accountId != account.id) r,
    ];
  } else {
    final own = db.alias(t, 'own');
    final found = <int, TransactionRecord>{
      if (kept.product != null)
        for (final r in await _named(db, kept.product!).get()) r.id: r,
      for (final r
          in await (db.select(t)..where(
                (t) =>
                    t.transferAccountId.equals(account.id) |
                    t.id.isInQuery(
                      db.selectOnly(own)
                        ..addColumns([own.transferPairId])
                        ..where(
                          own.accountId.equals(account.id) &
                              own.transferPairId.isNotNull(),
                        ),
                    ),
              ))
              .get())
        r.id: r,
    };
    candidates = [
      for (final r in found.values)
        if (r.accountId != account.id) r,
    ];
  }
  candidates.sort((a, b) {
    final byTime = a.occurredAt.compareTo(b.occurredAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  final partners = await _rowsById(db, [
    for (final r in candidates) ?r.transferPairId,
  ]);

  // Transactions on the account that are not entries yet: typed there, or
  // moved there. Corrections the person made stay as they are.
  final strays =
      await (db.select(t)..where(
            (t) =>
                t.accountId.equals(account.id) &
                (only == null
                    ? const Constant(true)
                    : t.id.isIn([for (final r in only) r.id])) &
                t.id.isNotInQuery(
                  db.selectOnly(db.savingsEntries)
                    ..addColumns([db.savingsEntries.transactionId]),
                ),
          ))
          .get();
  for (final row in strays) {
    if (row.kind == TransactionKind.correction) continue;
    await db
        .into(db.savingsEntries)
        .insert(
          SavingsEntriesCompanion.insert(
            transactionId: Value(row.id),
            kind: row.direction == TransactionDirection.inflow
                ? SavingsEntryKind.paidIn
                : SavingsEntryKind.takenOut,
          ),
        );
    // Money typed here has no message to wait for on another account.
    if (row.transferAccountId != null && row.transferPairId == null) {
      await (db.update(t)..where((t) => t.id.equals(row.id))).write(
        const TransactionsCompanion(transferAccountId: Value(null)),
      );
    }
  }

  final entries = {
    for (final e in await savingsEntriesOf(db, account.id)) e.row.id: e,
  };
  final mirrorOf = {
    for (final e in entries.values)
      if (isSavingsMirror(e) && e.row.transferPairId != null)
        e.row.transferPairId!: e,
  };

  final linked = <int>{};
  var refreshed = 0;
  var removed = 0;
  var skipped = 0;
  final wanted = <int>{};

  Future<SavingsPocketRow> pocketFor(String code) async {
    for (final p in pockets) {
      if (p.code == code) return p;
    }
    final live = [
      for (final p in pockets)
        if (!p.ignored) p,
    ];
    // The account's one pocket had no code until its first payment gave it.
    if (code.isNotEmpty && live.length == 1 && live.single.code.isEmpty) {
      await (db.update(db.savingsPockets)
            ..where((p) => p.id.equals(live.single.id)))
          .write(SavingsPocketsCompanion(code: Value(code)));
    } else {
      await db
          .into(db.savingsPockets)
          .insert(
            SavingsPocketsCompanion.insert(
              accountId: account.id,
              code: code,
              name: code.isEmpty ? account.name : code,
            ),
          );
    }
    pockets = await savingsPocketsOf(db, account.id);
    return pockets.firstWhere((p) => p.code == code);
  }

  for (var row in candidates) {
    final named = row.transferAccountId == account.id;
    final move = kept.moveOf(row);
    if (move == null && !named) continue;
    if (row.currency != account.currency) {
      if (move != null) skipped++;
      continue;
    }
    final partner = partners[row.transferPairId];
    final mirror = mirrorOf[row.id];
    if (partner != null && partner.id != mirror?.row.id) {
      // Its other side is already on this account, as the person matched
      // it there.
      if (partner.accountId == account.id) continue;
      // Matched with a transaction on another account.
      if (named || mirror != null || _pairedByHand(row, partner)) {
        if (move != null) skipped++;
        continue;
      }
      // Pairing matched it with something unrelated: undo that, for good.
      final out = row.direction == TransactionDirection.outflow;
      await db
          .into(db.declinedTransfers)
          .insertOnConflictUpdate(
            DeclinedTransfersCompanion.insert(
              outflowId: out ? row.id : partner.id,
              inflowId: out ? partner.id : row.id,
            ),
          );
      await (db.update(t)..where((t) => t.id.isIn([row.id, partner.id]))).write(
        const TransactionsCompanion(transferPairId: Value(null)),
      );
      row = row.copyWith(transferPairId: const Value(null));
    } else if (!named && mirror == null && row.transferAccountId != null) {
      // The person, or its account number, says it went to another account.
      skipped++;
      continue;
    }

    final paidIn = row.direction == TransactionDirection.outflow;
    int? pocketId;
    var coded = false;
    if (move is SavingsPayIn && move.code.isNotEmpty) {
      final pocket = await pocketFor(move.code);
      // Not the person's own goal: its payments stay as they were.
      if (pocket.ignored) continue;
      pocketId = pocket.id;
      coded = true;
    }
    wanted.add(row.id);

    if (mirror == null) {
      final mirrorId = await db
          .into(t)
          .insert(
            TransactionsCompanion.insert(
              accountId: account.id,
              occurredAt: row.occurredAt,
              amountMinor: row.amountMinor,
              direction: paidIn
                  ? TransactionDirection.inflow
                  : TransactionDirection.outflow,
              currency: Value(row.currency),
              source: TransactionSource.manual,
              transferPairId: Value(row.id),
              transferAccountId: Value(row.accountId),
            ),
          );
      await db
          .into(db.savingsEntries)
          .insert(
            SavingsEntriesCompanion.insert(
              transactionId: Value(mirrorId),
              pocketId: Value(pocketId),
              kind: paidIn
                  ? SavingsEntryKind.paidIn
                  : SavingsEntryKind.takenOut,
            ),
          );
      await (db.update(t)..where((t) => t.id.equals(row.id))).write(
        TransactionsCompanion(
          transferPairId: Value(mirrorId),
          transferAccountId: Value(account.id),
        ),
      );
      linked.add(row.id);
      continue;
    }

    // An existing mirror follows its payment.
    final m = mirror.row;
    final direction = paidIn
        ? TransactionDirection.inflow
        : TransactionDirection.outflow;
    var changed = false;
    if (!_sameSecond(m.occurredAt, row.occurredAt) ||
        m.amountMinor != row.amountMinor ||
        m.currency != row.currency ||
        m.direction != direction ||
        m.transferAccountId != row.accountId) {
      await (db.update(t)..where((t) => t.id.equals(m.id))).write(
        TransactionsCompanion(
          occurredAt: Value(row.occurredAt),
          amountMinor: Value(row.amountMinor),
          currency: Value(row.currency),
          direction: Value(direction),
          transferAccountId: Value(row.accountId),
        ),
      );
      changed = true;
    }
    if (row.transferPairId != m.id || row.transferAccountId != account.id) {
      await (db.update(t)..where((t) => t.id.equals(row.id))).write(
        TransactionsCompanion(
          transferPairId: Value(m.id),
          transferAccountId: Value(account.id),
        ),
      );
      changed = true;
    }
    final kind = paidIn ? SavingsEntryKind.paidIn : SavingsEntryKind.takenOut;
    if (mirror.entry.kind != kind ||
        (coded && mirror.entry.pocketId != pocketId)) {
      await (db.update(
        db.savingsEntries,
      )..where((e) => e.transactionId.equals(m.id))).write(
        SavingsEntriesCompanion(
          kind: Value(kind),
          pocketId: coded ? Value(pocketId) : const Value.absent(),
        ),
      );
      changed = true;
    }
    if (changed) refreshed++;
  }

  // Mirrors whose payment is gone, or is no longer this account's.
  final looked = {for (final r in candidates) r.id};
  for (final e in entries.values) {
    if (!isSavingsMirror(e)) continue;
    final pairId = e.row.transferPairId;
    if (pairId != null && wanted.contains(pairId)) continue;
    // Looking at some payments only says nothing about the others.
    if (only != null && (pairId == null || !looked.contains(pairId))) continue;
    // Its payment, when still here, goes back to how it was counted.
    if (pairId != null) {
      await (db.update(t)..where(
            (t) => t.id.equals(pairId) & t.transferAccountId.equals(account.id),
          ))
          .write(const TransactionsCompanion(transferAccountId: Value(null)));
    }
    await (db.update(t)..where((t) => t.transferPairId.equals(e.row.id))).write(
      const TransactionsCompanion(transferPairId: Value(null)),
    );
    await (db.delete(t)..where((t) => t.id.equals(e.row.id))).go();
    removed++;
  }

  await _assignPockets(db, account);
  await _settle(db, kept);
  return SavingsSync(
    linked: linked,
    refreshed: refreshed,
    removed: removed,
    skipped: skipped,
  );
}

/// [accountId]'s pockets, in the order they were first seen.
Future<List<SavingsPocketRow>> savingsPocketsOf(
  AppDatabase db,
  int accountId,
) =>
    (db.select(db.savingsPockets)
          ..where((p) => p.accountId.equals(accountId))
          ..orderBy([(p) => OrderingTerm.asc(p.id)]))
        .get();

/// Gives every account at least one pocket to type a balance for, and puts
/// money in or out that is in no pocket where the records can say: the only
/// pocket, or for money taken out, the only pocket open that day (see
/// [pocketForMoneyBack]). An entry leaves a pocket the person said is not
/// theirs. A pocket the person chose stays.
Future<void> _assignPockets(AppDatabase db, Account account) async {
  var pockets = await savingsPocketsOf(db, account.id);
  if (pockets.every((p) => p.ignored)) {
    final spare = pockets.where((p) => p.code.isEmpty).firstOrNull;
    if (spare != null) {
      await (db.update(db.savingsPockets)..where((p) => p.id.equals(spare.id)))
          .write(const SavingsPocketsCompanion(ignored: Value(false)));
    } else {
      await db
          .into(db.savingsPockets)
          .insert(
            SavingsPocketsCompanion.insert(
              accountId: account.id,
              code: '',
              name: account.name,
            ),
          );
    }
    pockets = await savingsPocketsOf(db, account.id);
  }
  final live = [
    for (final p in pockets)
      if (!p.ignored) p,
  ];
  final liveIds = {for (final p in live) p.id};
  final locks = [
    for (final p in live)
      (
        id: p.id,
        lockedUntil: p.lockedUntil == null
            ? null
            : CalendarDate.local(p.lockedUntil!),
      ),
  ];
  for (final e in await savingsEntriesOf(db, account.id)) {
    final kind = e.entry.kind;
    if (kind != SavingsEntryKind.paidIn && kind != SavingsEntryKind.takenOut) {
      continue;
    }
    if (liveIds.contains(e.entry.pocketId)) continue;
    final pocketId = kind == SavingsEntryKind.takenOut
        ? pocketForMoneyBack(locks, CalendarDate.local(e.row.occurredAt))
        : live.length == 1
        ? live.single.id
        : null;
    if (pocketId == e.entry.pocketId) continue;
    await (db.update(db.savingsEntries)
          ..where((s) => s.transactionId.equals(e.row.id)))
        .write(SavingsEntriesCompanion(pocketId: Value(pocketId)));
  }
}

/// What each of [accountId]'s pockets holds, by pocket id: its last typed
/// balance and the money in and out since (see [settlePocket]). Pockets
/// the person said are not theirs are left out.
Future<Map<int, int>> savingsPocketBalances(
  AppDatabase db,
  int accountId,
) async {
  final (:settled, entries: _) = await _settled(db, accountId);
  return {
    for (final MapEntry(key: id, value: pocket) in settled.pockets.entries)
      id: pocket.balanceMinor,
  };
}

/// [accountId]'s pockets worked out from its entries and typed balances,
/// with the entries read for it.
Future<({AccountSettlement settled, List<SavingsEntryRecord> entries})>
_settled(AppDatabase db, int accountId) async {
  final live = {
    for (final p in await savingsPocketsOf(db, accountId))
      if (!p.ignored) p.id,
  };
  final entries = await savingsEntriesOf(db, accountId);
  final flows = <int, List<PocketFlow>>{for (final id in live) id: []};
  for (final e in entries) {
    final sign = switch (e.entry.kind) {
      SavingsEntryKind.paidIn => 1,
      SavingsEntryKind.takenOut => -1,
      SavingsEntryKind.interest || SavingsEntryKind.correction => 0,
    };
    final pocketId = e.entry.pocketId;
    if (sign == 0 || pocketId == null || !live.contains(pocketId)) continue;
    flows[pocketId]!.add(
      PocketFlow(e.row.occurredAt, sign * e.row.amountMinor),
    );
  }
  final readings = <int, List<PocketReading>>{for (final id in live) id: []};
  if (live.isNotEmpty) {
    for (final r in await (db.select(
      db.savingsReadings,
    )..where((r) => r.pocketId.isIn(live))).get()) {
      readings[r.pocketId]!.add(
        PocketReading(
          at: r.at,
          balanceMinor: r.balanceMinor,
          gapIsInterest: r.gapIsInterest,
        ),
      );
    }
  }
  return (
    settled: settleAccount(flows: flows, readings: readings),
    entries: entries,
  );
}

/// The income category interest is filed under, made on first use. A
/// category of the person's own called Interest that is not income, such as
/// interest paid on a loan, is left as it is.
Future<int> _interestCategory(AppDatabase db) async {
  final keyed = await (db.select(
    db.categories,
  )..where((c) => c.key.equals(interestSeed.key))).getSingleOrNull();
  if (keyed != null) return keyed.id;
  final named =
      await (db.select(db.categories)..where(
            (c) => c.name.lower().equals(interestSeed.name.toLowerCase()),
          ))
          .getSingleOrNull();
  if (named == null || named.type == interestSeed.type) {
    return ensureCategory(db, interestSeed);
  }
  return ensureCategory(db, interestEarnedSeed);
}

Future<void> _settle(AppDatabase db, _Kept kept) async {
  final account = kept.account;
  final t = db.transactions;
  final (:settled, :entries) = await _settled(db, account.id);

  // What each update should have recorded, by kind and time.
  final want = <(SavingsEntryKind, int), (DateTime, int)>{};
  for (final u in settled.updates) {
    final second = u.at.millisecondsSinceEpoch ~/ 1000;
    if (u.interestMinor > 0) {
      want[(SavingsEntryKind.interest, second)] = (u.at, u.interestMinor);
    }
    if (u.correctionMinor != 0) {
      want[(SavingsEntryKind.correction, second)] = (u.at, u.correctionMinor);
    }
  }
  for (final e in entries) {
    final kind = e.entry.kind;
    if (kind != SavingsEntryKind.interest &&
        kind != SavingsEntryKind.correction) {
      continue;
    }
    final key = (kind, e.row.occurredAt.millisecondsSinceEpoch ~/ 1000);
    final wanted = want.remove(key);
    if (wanted == null) {
      await (db.delete(t)..where((t) => t.id.equals(e.row.id))).go();
      continue;
    }
    final (_, minor) = wanted;
    final direction = minor < 0
        ? TransactionDirection.outflow
        : TransactionDirection.inflow;
    if (e.row.amountMinor != minor.abs() || e.row.direction != direction) {
      await (db.update(t)..where((t) => t.id.equals(e.row.id))).write(
        TransactionsCompanion(
          amountMinor: Value(minor.abs()),
          direction: Value(direction),
        ),
      );
    }
  }
  int? interestCategory;
  for (final MapEntry(key: (kind, _), value: (at, minor)) in want.entries) {
    final interest = kind == SavingsEntryKind.interest;
    if (interest) interestCategory ??= await _interestCategory(db);
    final id = await db
        .into(t)
        .insert(
          TransactionsCompanion.insert(
            accountId: account.id,
            occurredAt: at,
            amountMinor: minor.abs(),
            direction: minor < 0
                ? TransactionDirection.outflow
                : TransactionDirection.inflow,
            kind: Value(interest ? null : TransactionKind.correction),
            currency: Value(account.currency),
            source: TransactionSource.manual,
            counterpartyName: Value(
              interest
                  ? '${kept.product?.name ?? account.name} interest'
                  : null,
            ),
            categoryOverrideId: Value(interest ? interestCategory : null),
          ),
        );
    await db
        .into(db.savingsEntries)
        .insert(
          SavingsEntriesCompanion.insert(transactionId: Value(id), kind: kind),
        );
  }

  // The account opens with its first entry: balances leave out anything
  // dated before an account's opening.
  final first =
      await (db.selectOnly(t)
            ..addColumns([t.occurredAt.min()])
            ..where(t.accountId.equals(account.id)))
          .map((row) => row.read(t.occurredAt.min()))
          .getSingle();
  if (first != null && first.isBefore(account.openingDate)) {
    await (db.update(db.accounts)..where((a) => a.id.equals(account.id))).write(
      AccountsCompanion(openingDate: Value(first)),
    );
  }
}
