import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

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
  JournalRepository(this._db, {DateTime Function()? clock, this._changes})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The ledger's changes, the same updates `ledgerChangesProvider` counts.
  final Stream<void>? _changes;
  StreamSubscription<void>? _counting;
  int _generation = 0;

  /// How many changes the ledger has seen since this was first asked, so
  /// [readJournal] can share one read per change. A plain counter fed by
  /// the database rather than provider state: touching
  /// `ledgerChangesProvider` (or a provider that depends on the ledger)
  /// part-way through a provider would rebuild one that is only read, not
  /// listened to, mid-computation, and it would then wait for good.
  int get generation {
    _counting ??= _changes?.listen((_) => _generation++);
    return _generation;
  }

  /// Stops counting changes.
  void dispose() => _counting?.cancel();

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
    final writes = _JournalWrites();
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
          writes.reverse(s, now);
          reversed++;
        }
      }
      if (kept) continue;
      writes.post(e, rateOf(e), now);
      posted++;
    }
    for (final gone in byKey.values.expand((s) => s)) {
      writes.reverse(gone, now);
      reversed++;
    }
    await writes.flush(_db);
    return JournalSync(posted: posted, reversed: reversed);
  }

  /// Entries that are neither reversed nor reversals, with their postings:
  /// those of [accountIds], or all of them.
  Future<List<_Stored>> _live(Set<int>? accountIds) async {
    final ids = accountIds?.toList();
    final rows = await _withPostings(
      'j.reverses IS NULL AND j.id NOT IN '
      '(SELECT reverses FROM journal_entries WHERE reverses IS NOT NULL)'
      '${ids == null ? '' : ' AND j.account_id IN (${List.filled(ids.length, '?').join(', ')})'}',
      [for (final id in ids ?? const <int>[]) Variable(id)],
    );
    return [
      for (final (row, lines) in rows)
        _Stored(
          row,
          lines,
          _shape(row.occurredAt, row.memo, row.accountId, [
            for (final p in lines) (p.account, p.amountMinor, p.currency),
          ], lines.firstOrNull?.rateMicros),
        ),
    ];
  }

  /// The journal entries matching [where] (on `j`, the entries table) with
  /// their postings, in the order they were posted.
  ///
  /// One query read column by column: the typed join drift builds reads
  /// every column of both tables through a map per row, which took most of
  /// a journal read.
  Future<List<(JournalEntryRow, List<Posting>)>> _withPostings(
    String? where, [
    List<Variable<Object>> variables = const [],
  ]) async {
    final j = _db.journalEntries;
    final p = _db.postings;
    final types = _db.typeMapping;
    final rows = await _db
        .customSelect(
          'SELECT j.id, j.occurred_at, j.source_kind, j.source_id, j.memo, '
          'j.reverses, j.recorded_at, j.account_id, p.id AS posting_id, '
          'p.account, p.amount_minor, p.currency, p.rate_micros '
          'FROM journal_entries j LEFT JOIN postings p ON p.entry_id = j.id'
          '${where == null ? '' : ' WHERE $where'} ORDER BY j.id, p.id',
          variables: variables,
          readsFrom: {j, p},
        )
        .get();
    final out = <(JournalEntryRow, List<Posting>)>[];
    final sources = <String, JournalSource>{};
    for (final row in rows) {
      final data = row.data;
      final id = data['id']! as int;
      if (out.isEmpty || out.last.$1.id != id) {
        final kind = data['source_kind']! as String;
        out.add((
          JournalEntryRow(
            id: id,
            occurredAt: types.read(DriftSqlType.dateTime, data['occurred_at'])!,
            sourceKind: sources[kind] ??= $JournalEntriesTable
                .$convertersourceKind
                .fromSql(kind),
            sourceId: data['source_id']! as int,
            memo: data['memo'] as String?,
            reverses: data['reverses'] as int?,
            recordedAt: types.read(DriftSqlType.dateTime, data['recorded_at'])!,
            accountId: data['account_id'] as int?,
          ),
          [],
        ));
      }
      final postingId = data['posting_id'] as int?;
      if (postingId == null) continue;
      out.last.$2.add(
        Posting(
          id: postingId,
          entryId: id,
          account: data['account']! as String,
          amountMinor: data['amount_minor']! as int,
          currency: data['currency']! as String,
          rateMicros: data['rate_micros'] as int?,
        ),
      );
    }
    return out;
  }

  /// Every stored entry, reversals and the entries they cancel included (so
  /// they net out), after a [sync]. With [converter], postings in another
  /// currency count in its base, at the rate the person got for their
  /// transaction or else the rates of the day, as transactions do; without
  /// a rate they keep their own currency.
  Future<List<JournalEntry>> entries({CurrencyConverter? converter}) async {
    await sync();
    final byEntry = [
      for (final (row, postings) in await _withPostings(null))
        if (postings.isNotEmpty) (row, postings),
    ];
    final got = converter == null
        ? const <int, TransactionRecord>{}
        : {
            for (final t in await (_db.select(
              _db.transactions,
            )..where((t) => t.fxRateMicros.isNotNull())).get())
              t.id: t,
          };
    final out = <JournalEntry>[];
    for (final (row, postings) in byEntry) {
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

/// The entries and postings one repost adds, written in one batch: a
/// round trip per row took most of a large sync, more so on a phone, where
/// the database runs in its own isolate. Rows go in the order they were
/// added, with the ids the database would have given them one at a time.
class _JournalWrites {
  final _rows = <(JournalEntriesCompanion, List<PostingsCompanion>)>[];

  void post(JournalEntry e, int? rate, DateTime now) => _rows.add((
    JournalEntriesCompanion.insert(
      occurredAt: e.at,
      sourceKind: e.source,
      sourceId: e.sourceId,
      memo: Value(e.memo),
      recordedAt: now,
      accountId: Value(e.accountId),
    ),
    [
      for (final l in e.lines)
        _posting(l.account.key, l.amountMinor, e.currency, rate),
    ],
  ));

  void reverse(_Stored s, DateTime now) => _rows.add((
    JournalEntriesCompanion.insert(
      occurredAt: s.row.occurredAt,
      sourceKind: s.row.sourceKind,
      sourceId: s.row.sourceId,
      memo: Value(s.row.memo),
      reverses: Value(s.row.id),
      recordedAt: now,
      accountId: Value(s.row.accountId),
    ),
    [
      for (final p in s.postings)
        _posting(p.account, -p.amountMinor, p.currency, p.rateMicros),
    ],
  ));

  static PostingsCompanion _posting(
    String account,
    int amountMinor,
    String currency,
    int? rateMicros,
  ) => PostingsCompanion.insert(
    // Filled in by [flush], once the entry's id is known.
    entryId: 0,
    account: account,
    amountMinor: amountMinor,
    currency: currency,
    rateMicros: Value(rateMicros),
  );

  /// Writes everything added, inside the caller's transaction.
  Future<void> flush(AppDatabase db) async {
    if (_rows.isEmpty) return;
    // The id AUTOINCREMENT would give next: past every id ever used.
    final next = await db
        .customSelect(
          'SELECT MAX(COALESCE((SELECT seq FROM sqlite_sequence '
          "WHERE name = 'journal_entries'), 0), "
          'COALESCE((SELECT MAX(id) FROM journal_entries), 0)) + 1 AS next',
          readsFrom: {db.journalEntries},
        )
        .map((row) => row.read<int>('next'))
        .getSingle();
    await db.batch((b) {
      for (final (i, (entry, postings)) in _rows.indexed) {
        final id = next + i;
        b.insert(db.journalEntries, entry.copyWith(id: Value(id)));
        b.insertAll(db.postings, [
          for (final p in postings) p.copyWith(entryId: Value(id)),
        ]);
      }
    });
    _rows.clear();
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

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  final repository = JournalRepository(
    ref.watch(appDatabaseProvider),
    // From the database, not from a provider: see [generation].
    changes: ledgerTableUpdates(ref.watch(appDatabaseProvider)),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The open space's journal balances at one ledger generation (how many
/// changes the ledger has seen), read through one repository (which holds
/// the space's database) with one currency converter. Every provider that
/// reads the journal at that generation shares this one read.
///
/// The repository is part of the key because each space's generation
/// starts at zero: keyed by generation and converter alone, a space opened
/// after another was handed that space's balances once their counts met.
///
/// It depends on nothing that changes: a change to the ledger or to the
/// rates makes a new key rather than invalidating this one while its readers
/// are still computing. The newest key is kept alive, so a reader that is
/// only read (not listened to) still gets its value; older keys are let go
/// once the next one is read and nothing watches them. A key of another
/// repository (another space) is always the newest.
final journalAtGenerationProvider = FutureProvider.autoDispose
    .family<JournalBalances, (int, CurrencyConverter, JournalRepository)>((
      ref,
      key,
    ) {
      final (generation, converter, journal) = key;
      final latest = ref.read(_latestJournalProvider);
      final link = ref.keepAlive();
      final newest = latest.generation;
      if (newest == null ||
          !identical(latest.journal, journal) ||
          generation >= newest) {
        final older = latest.link;
        latest
          ..link = link
          ..generation = generation
          ..journal = journal;
        older?.close();
      } else {
        link.close();
      }
      return journal.read(converter: converter);
    });

/// The newest journal generation read, kept alive until the next.
class _LatestJournal {
  KeepAliveLink? link;
  int? generation;
  JournalRepository? journal;
}

final _latestJournalProvider = Provider<_LatestJournal>(
  (ref) => _LatestJournal(),
);

/// The open space's balances, read from its journal once per change to the
/// ledger and shared by every provider that calls this. Providers that call
/// it watch `ledgerChangesProvider` themselves, so they follow every change.
Future<JournalBalances> readJournal(Ref ref) {
  final journal = ref.watch(journalRepositoryProvider);
  final converter = ref.watch(currencyConverterProvider);
  return ref.watch(
    journalAtGenerationProvider((journal.generation, converter, journal))
        .future,
  );
}
