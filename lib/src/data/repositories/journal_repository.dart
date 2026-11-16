import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../domain/books/book_account.dart';
import '../../domain/books/books.dart';
import '../../domain/books/journal.dart';
import '../../domain/books/journal_balances.dart';
import '../../domain/ledger/balances.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../../features/currency/application/currency_controller.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'accounts_repository.dart';
import 'transactions_repository.dart';

/// What one [JournalRepository.sync] or [JournalRepository.rebuild] did.
class JournalSync {
  const JournalSync({required this.posted, required this.reversed});

  static const none = JournalSync(posted: 0, reversed: 0);

  /// New entries posted, replacements included.
  final int posted;

  /// Entries reversed: their source changed or is gone.
  final int reversed;

  bool get changed => posted > 0 || reversed > 0;

  @override
  String toString() => 'JournalSync(posted: $posted, reversed: $reversed)';
}

/// The open space's double-entry journal (decision 0018), kept in the
/// space's own database. Balances, On hand and everything that shows money
/// held read it through [read].
///
/// Entries are worked out with [postJournal]. [sync] reposts only the
/// accounts the database's triggers marked as changed (see `JournalDirty`);
/// [rebuild] reposts every account, for the upgrade and for repair. Either
/// way an entry whose source changed (a recategorise, a move, an own
/// transfer matched or unmatched) or is gone gets a reversal and then the
/// new entry. Nothing is edited or deleted, and running either again
/// changes nothing.
class JournalRepository {
  JournalRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The records of [accountIds], or of every account, read as balances
  /// read them but in their own currency.
  Future<
    ({
      List<AccountOpening> accounts,
      List<LedgerEntry> history,
      Map<int, BookCategory> categories,
    })
  >
  _records([Set<int>? accountIds]) async => (
    accounts: [
      for (final a in await DriftAccountsRepository(_db).openings())
        if (accountIds == null || accountIds.contains(a.id)) a,
    ],
    history: await DriftTransactionsRepository(_db).ledgerEntries(
      from: DateTime.utc(1970),
      to: DateTime.utc(9999),
      accountIds: accountIds,
    ),
    categories: {
      for (final c in await _db.select(_db.categories).get())
        c.id: (key: c.key, type: c.type),
    },
  );

  /// Reposts the accounts marked as changed since the last sync.
  Future<JournalSync> sync() => _db.transaction(() async {
    final dirty = {
      for (final d in await _db.select(_db.journalDirty).get()) d.accountId,
    };
    if (dirty.isEmpty) return JournalSync.none;
    final done = await _repost(dirty.contains(_rebuildAll) ? null : dirty);
    await (_db.delete(
      _db.journalDirty,
    )..where((d) => d.accountId.isIn(dirty))).go();
    return done;
  });

  /// Reposts every account, and reverses entries that belong to none.
  Future<JournalSync> rebuild() => _db.transaction(() async {
    final done = await _repost(null);
    await _db.delete(_db.journalDirty).go();
    return done;
  });

  /// Reposts [accountIds], or everything.
  Future<JournalSync> _repost(Set<int>? accountIds) async {
    final r = await _records(accountIds);
    final wanted = postJournal(
      accounts: r.accounts,
      history: r.history,
      categories: r.categories,
    );
    final rates = {
      for (final t in await (_db.select(
        _db.transactions,
      )..where((t) => t.fxRateMicros.isNotNull())).get())
        t.id: t.fxRateMicros!,
    };
    int? rateOf(JournalEntry e) =>
        e.source == JournalSource.transaction ? rates[e.sourceId] : null;

    final byKey = <(JournalSource, int), List<_Stored>>{};
    for (final s in await _live(accountIds)) {
      (byKey[(s.row.sourceKind, s.row.sourceId)] ??= []).add(s);
    }
    var posted = 0;
    var reversed = 0;
    final now = _clock();
    for (final e in wanted) {
      final shape = _shape(e.at, e.memo, e.accountId, [
        for (final l in e.lines) (l.account.key, l.amountMinor, e.currency),
      ], rateOf(e));
      final stored = byKey.remove((e.source, e.sourceId)) ?? const [];
      var kept = false;
      for (final s in stored) {
        if (!kept && s.shape == shape) {
          kept = true;
        } else {
          await _reverse(s, now);
          reversed++;
        }
      }
      if (kept) continue;
      await _post(e, rateOf(e), now);
      posted++;
    }
    for (final gone in byKey.values.expand((s) => s)) {
      await _reverse(gone, now);
      reversed++;
    }
    return JournalSync(posted: posted, reversed: reversed);
  }

  /// Entries that are neither reversed nor reversals, with their postings:
  /// those of [accountIds], or all of them.
  Future<List<_Stored>> _live(Set<int>? accountIds) async {
    final j = _db.journalEntries;
    final ids = accountIds?.toList();
    final rows = await _db
        .customSelect(
          'SELECT * FROM journal_entries WHERE reverses IS NULL AND id NOT IN '
          '(SELECT reverses FROM journal_entries WHERE reverses IS NOT NULL)'
          '${ids == null ? '' : ' AND account_id IN (${List.filled(ids.length, '?').join(', ')})'}',
          variables: [for (final id in ids ?? const <int>[]) Variable(id)],
          readsFrom: {j},
        )
        .map((row) => j.map(row.data))
        .get();
    final lines = <int, List<Posting>>{};
    final entryIds = [for (final r in rows) r.id];
    // In slices, to stay under SQLite's limit on bound values.
    for (var i = 0; i < entryIds.length; i += _slice) {
      final slice = entryIds.sublist(
        i,
        i + _slice > entryIds.length ? entryIds.length : i + _slice,
      );
      for (final p in await (_db.select(
        _db.postings,
      )..where((p) => p.entryId.isIn(slice))).get()) {
        (lines[p.entryId] ??= []).add(p);
      }
    }
    return [
      for (final row in rows)
        _Stored(
          row,
          lines[row.id] ?? const [],
          _shape(row.occurredAt, row.memo, row.accountId, [
            for (final p in lines[row.id] ?? const <Posting>[])
              (p.account, p.amountMinor, p.currency),
          ], (lines[row.id] ?? const <Posting>[]).firstOrNull?.rateMicros),
        ),
    ];
  }

  static const _slice = 500;

  Future<void> _post(JournalEntry e, int? rate, DateTime now) async {
    final id = await _db
        .into(_db.journalEntries)
        .insert(
          JournalEntriesCompanion.insert(
            occurredAt: e.at,
            sourceKind: e.source,
            sourceId: e.sourceId,
            memo: Value(e.memo),
            recordedAt: now,
            accountId: Value(e.accountId),
          ),
        );
    for (final l in e.lines) {
      await _db
          .into(_db.postings)
          .insert(
            PostingsCompanion.insert(
              entryId: id,
              account: l.account.key,
              amountMinor: l.amountMinor,
              currency: e.currency,
              rateMicros: Value(rate),
            ),
          );
    }
  }

  Future<void> _reverse(_Stored s, DateTime now) async {
    final id = await _db
        .into(_db.journalEntries)
        .insert(
          JournalEntriesCompanion.insert(
            occurredAt: s.row.occurredAt,
            sourceKind: s.row.sourceKind,
            sourceId: s.row.sourceId,
            memo: Value(s.row.memo),
            reverses: Value(s.row.id),
            recordedAt: now,
            accountId: Value(s.row.accountId),
          ),
        );
    for (final p in s.postings) {
      await _db
          .into(_db.postings)
          .insert(
            PostingsCompanion.insert(
              entryId: id,
              account: p.account,
              amountMinor: -p.amountMinor,
              currency: p.currency,
              rateMicros: Value(p.rateMicros),
            ),
          );
    }
  }

  /// Every stored entry, reversals and the entries they cancel included (so
  /// they net out), after a [sync]. With [converter], postings in another
  /// currency count in its base, at the rate the person got for their
  /// transaction or else the rates of the day, as transactions do; without
  /// a rate they keep their own currency.
  Future<List<JournalEntry>> entries({CurrencyConverter? converter}) async {
    await sync();
    final j = _db.journalEntries;
    final p = _db.postings;
    final query = _db.select(p).join([innerJoin(j, j.id.equalsExp(p.entryId))]);
    final byEntry = <int, (JournalEntryRow, List<Posting>)>{};
    for (final row in await query.get()) {
      final entry = row.readTable(j);
      (byEntry[entry.id] ??= (entry, [])).$2.add(row.readTable(p));
    }
    final got = converter == null
        ? const <int, TransactionRecord>{}
        : {
            for (final t in await (_db.select(
              _db.transactions,
            )..where((t) => t.fxRateMicros.isNotNull())).get())
              t.id: t,
          };
    final out = <JournalEntry>[];
    for (final (row, postings) in byEntry.values) {
      // An entry's postings share one currency.
      final currency = postings.first.currency;
      final record = row.sourceKind == JournalSource.transaction
          ? got[row.sourceId]
          : null;
      int? inBase(int minor) {
        if (converter == null || currency == converter.base) return minor;
        return converter
            .convert(
              minor,
              currency,
              row.occurredAt,
              gotCurrency: record?.fxRateCurrency,
              gotRate: record?.fxRateMicros == null
                  ? null
                  : record!.fxRateMicros! / 1e6,
            )
            ?.baseMinor;
      }

      final converted = [
        for (final l in postings)
          if (BookAccount.parse(l.account) case final account?)
            (account, inBase(l.amountMinor)),
      ];
      final allConverted = converted.every((c) => c.$2 != null);
      final lines = allConverted
          ? [for (final (a, m) in converted) JournalLine(a, m!)]
          : [
              for (final l in postings)
                if (BookAccount.parse(l.account) case final account?)
                  JournalLine(account, l.amountMinor),
            ];
      // Rounding each line on its own can leave a unit over: the largest
      // line takes it, so the entry still balances.
      if (allConverted && lines.length > 1) {
        final over = lines.fold(0, (s, l) => s + l.amountMinor);
        if (over != 0) {
          var big = 0;
          for (var i = 1; i < lines.length; i++) {
            if (lines[i].amountMinor.abs() > lines[big].amountMinor.abs()) {
              big = i;
            }
          }
          lines[big] = JournalLine(
            lines[big].account,
            lines[big].amountMinor - over,
          );
        }
      }
      out.add(
        JournalEntry(
          source: row.sourceKind,
          sourceId: row.sourceId,
          at: row.occurredAt,
          currency: allConverted && converter != null
              ? converter.base
              : currency,
          accountId: row.accountId,
          memo: row.memo,
          lines: lines,
        ),
      );
    }
    return out;
  }

  /// The journal's balances, after a [sync] (see [entries]).
  Future<JournalBalances> read({CurrencyConverter? converter}) async =>
      JournalBalances(await entries(converter: converter));

  /// Each account's stored balance in each currency from entries dated
  /// before [at] (all of them without), positive in the account's normal
  /// direction. Reversals and the entries they cancel both count, so they
  /// net out.
  Future<Map<(BookAccount, String), int>> balances({DateTime? at}) async {
    final j = _db.journalEntries;
    final p = _db.postings;
    final query = _db.select(p).join([innerJoin(j, j.id.equalsExp(p.entryId))]);
    if (at != null) query.where(j.occurredAt.isSmallerThanValue(at));
    final sums = <(String, String), int>{};
    for (final row in await query.get()) {
      final posting = row.readTable(p);
      final key = (posting.account, posting.currency);
      sums[key] = (sums[key] ?? 0) + posting.amountMinor;
    }
    return {
      for (final MapEntry(key: (key, currency), :value) in sums.entries)
        if (BookAccount.parse(key) case final account?)
          (account, currency): account.debitNormal ? value : -value,
    };
  }

  /// Entries whose postings do not sum to zero in each currency. Empty
  /// unless something is wrong.
  Future<List<int>> unbalanced() async {
    final sums = <(int, String), int>{};
    for (final p in await _db.select(_db.postings).get()) {
      final key = (p.entryId, p.currency);
      sums[key] = (sums[key] ?? 0) + p.amountMinor;
    }
    return {
      for (final MapEntry(key: (id, _), :value) in sums.entries)
        if (value != 0) id,
    }.toList()..sort();
  }

  /// What each account's reported balances do not explain: the gaps their
  /// assertions left in Not yet sorted, by account id. Accounts whose
  /// balances all reconcile are left out.
  Future<Map<int, int>> openGaps() async {
    final out = <int, int>{};
    for (final e in await entries()) {
      if (e.source != JournalSource.balanceDifference) continue;
      final id = e.accountId;
      if (id == null) continue;
      for (final l in e.lines) {
        if (l.account == BookAccount.money(id)) {
          out[id] = (out[id] ?? 0) + l.amountMinor;
        }
      }
    }
    out.removeWhere((_, gap) => gap == 0);
    return out;
  }

  /// Fills in the account of entries posted before entries carried one
  /// (version 34): the money account they post to, or their transaction's.
  static Future<void> tagAccounts(AppDatabase db) async {
    await db.customStatement(
      'UPDATE journal_entries SET account_id = source_id '
      "WHERE account_id IS NULL AND source_kind = 'opening'",
    );
    await db.customStatement(
      'UPDATE journal_entries SET account_id = (SELECT CAST(substr(p.account, '
      '7) AS INTEGER) FROM postings p WHERE p.entry_id = journal_entries.id '
      "AND p.account LIKE 'money:%' LIMIT 1) WHERE account_id IS NULL",
    );
    await db.customStatement(
      'UPDATE journal_entries SET account_id = (SELECT t.account_id FROM '
      'transactions t WHERE t.id = journal_entries.source_id) '
      'WHERE account_id IS NULL',
    );
  }

  /// Rebuilds the journal from the records after an upgrade that changed
  /// it, and logs accounts whose reported balances do not reconcile. A
  /// failure leaves the journal to the next [rebuild] from the app (see
  /// [JournalKeeper]): the space still opens.
  static Future<void> backfill(AppDatabase db) async {
    try {
      final journal = JournalRepository(db);
      await journal.rebuild();
      final open = await journal.openGaps();
      if (open.isNotEmpty && kDebugMode) {
        debugPrint('Journal accounts with balances that do not add up: $open');
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Building the journal failed: $error');
      await db
          .into(db.journalDirty)
          .insertOnConflictUpdate(
            const JournalDirtyCompanion(accountId: Value(_rebuildAll)),
          );
    }
  }

  /// Marks the whole journal for a rebuild, when an account id cannot.
  static const _rebuildAll = -1;
}

/// Adds the triggers that mark accounts for [JournalRepository.sync]: any
/// change to an account's transactions or to the account, and any change
/// to a payee or category, which can change what its transactions mean.
/// Safe to run again.
Future<void> createJournalTriggers(AppDatabase db) async {
  // Each mark skips accounts already marked rather than relying on a
  // conflict clause: in a trigger, the conflict handling of the statement
  // that fired it wins, so OR IGNORE would not hold under an upsert.
  String mark(String id) =>
      'INSERT INTO journal_dirty (account_id) SELECT $id WHERE NOT EXISTS '
      '(SELECT 1 FROM journal_dirty WHERE account_id = $id);';
  String markAll(String column, String from) =>
      'INSERT INTO journal_dirty (account_id) SELECT DISTINCT $column $from '
      'AND $column NOT IN (SELECT account_id FROM journal_dirty);';
  final everyAccount = markAll('id', 'FROM accounts WHERE 1');
  final payeeAccounts = markAll(
    'account_id',
    'FROM transactions WHERE payee_id = OLD.id',
  );
  final triggers = {
    'journal_dirty_transaction_insert':
        'AFTER INSERT ON transactions BEGIN ${mark('NEW.account_id')} END',
    'journal_dirty_transaction_update':
        'AFTER UPDATE ON transactions BEGIN ${mark('OLD.account_id')} '
        '${mark('NEW.account_id')} END',
    'journal_dirty_transaction_delete':
        'AFTER DELETE ON transactions BEGIN ${mark('OLD.account_id')} END',
    'journal_dirty_account_insert':
        'AFTER INSERT ON accounts BEGIN ${mark('NEW.id')} END',
    'journal_dirty_account_update':
        'AFTER UPDATE ON accounts BEGIN ${mark('OLD.id')} END',
    'journal_dirty_account_delete':
        'AFTER DELETE ON accounts BEGIN ${mark('OLD.id')} END',
    'journal_dirty_category_update':
        'AFTER UPDATE ON categories BEGIN $everyAccount END',
    'journal_dirty_category_delete':
        'AFTER DELETE ON categories BEGIN $everyAccount END',
    'journal_dirty_payee_update':
        'AFTER UPDATE ON payees BEGIN $payeeAccounts END',
    'journal_dirty_payee_delete':
        'AFTER DELETE ON payees BEGIN $payeeAccounts END',
  };
  for (final MapEntry(key: name, value: body) in triggers.entries) {
    await db.customStatement('CREATE TRIGGER IF NOT EXISTS $name $body');
  }
}

/// A stored live entry, with its postings and their shape for comparing.
class _Stored {
  _Stored(this.row, this.postings, this.shape);

  final JournalEntryRow row;
  final List<Posting> postings;
  final String shape;
}

/// A comparable form of an entry: its date to the second (as stored), memo,
/// account, rate and postings in a fixed order.
String _shape(
  DateTime at,
  String? memo,
  int? accountId,
  List<(String, int, String)> lines,
  int? rate,
) {
  final sorted = [for (final (a, m, c) in lines) '$a=$m $c']..sort();
  return '${at.millisecondsSinceEpoch ~/ 1000}|${memo ?? ''}|'
      '${accountId ?? ''}|${rate ?? ''}|${sorted.join(',')}';
}

/// Keeps a space database's journal posted as its records change: every
/// write to transactions, payees, categories, accounts or declined
/// transfers, from anywhere in the app, runs a [JournalRepository.sync].
/// Syncs never overlap; changes during one run another after it.
class JournalKeeper {
  JournalKeeper(this._db, {JournalRepository? journal})
    : _journal = journal ?? JournalRepository(_db);

  final AppDatabase _db;
  final JournalRepository _journal;
  StreamSubscription<void>? _changes;
  Future<void>? _running;
  var _again = false;
  var _stopped = false;

  /// Starts following changes. It never opens the database itself, which
  /// must wait for app lock: the first change after it opens syncs what
  /// changed, including what was written while no keeper followed, such as
  /// from another space's screens.
  void start() {
    _changes ??= _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.transactions,
            _db.payees,
            _db.categories,
            _db.accounts,
            _db.declinedTransfers,
          ]),
        )
        .listen((_) => poke());
  }

  /// Syncs now, or once more after the sync under way.
  void poke() {
    if (_stopped) return;
    if (_running != null) {
      _again = true;
      return;
    }
    _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      try {
        await _journal.sync();
      } on Object catch (error) {
        // Best effort: reading the journal syncs again.
        if (kDebugMode) debugPrint('Posting the journal failed: $error');
      }
    } while (_again && !_stopped);
  }

  /// Completes once no sync is running or due.
  Future<void> get idle async {
    while (_running != null) {
      await _running;
    }
  }

  /// Stops following changes and waits for a sync under way.
  Future<void> stop() async {
    _stopped = true;
    await _changes?.cancel();
    _changes = null;
    await idle;
  }
}

final journalRepositoryProvider = Provider<JournalRepository>(
  (ref) => JournalRepository(ref.watch(appDatabaseProvider)),
);

/// The open space's balances, read from its journal. Providers that call
/// it watch `ledgerChangesProvider` themselves, so they follow every change;
/// a provider of its own would add a dependency that can change while they
/// compute.
Future<JournalBalances> readJournal(Ref ref) => ref
    .watch(journalRepositoryProvider)
    .read(converter: ref.watch(currencyConverterProvider));
