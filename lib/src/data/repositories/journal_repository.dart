import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../domain/books/book_account.dart';
import '../../domain/books/books.dart';
import '../../domain/books/journal.dart';
import '../../domain/ledger/balances.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../database/app_database.dart';
import 'accounts_repository.dart';
import 'transactions_repository.dart';

/// What one [JournalRepository.sync] did.
class JournalSync {
  const JournalSync({required this.posted, required this.reversed});

  /// New entries posted, replacements included.
  final int posted;

  /// Entries reversed: their source changed or is gone.
  final int reversed;

  bool get changed => posted > 0 || reversed > 0;

  @override
  String toString() => 'JournalSync(posted: $posted, reversed: $reversed)';
}

/// An account whose journal balance is not what the balance code shows.
class JournalMismatch {
  const JournalMismatch({
    required this.account,
    required this.currency,
    required this.journalMinor,
    required this.recordsMinor,
  });

  final BookAccount account;
  final String currency;
  final int journalMinor;
  final int recordsMinor;

  @override
  String toString() =>
      'JournalMismatch($account $currency: journal $journalMinor, '
      'records $recordsMinor)';
}

/// The open space's double-entry journal (decision 0018), kept in the
/// space's own database. Stage 1: it is written, never read by the app.
///
/// [sync] posts what the records say: it works out every entry with
/// [postJournal], posts the ones not posted yet and, for any whose source
/// changed (a recategorise, a move, an own transfer matched or unmatched) or
/// is gone, posts a reversal and then the new entry. Nothing is edited or
/// deleted, and running it again changes nothing.
class JournalRepository {
  JournalRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Every record, read as balances read them but in its own currency.
  Future<
    ({
      List<AccountOpening> accounts,
      List<LedgerEntry> history,
      Map<int, BookCategory> categories,
    })
  >
  _records() async => (
    accounts: await DriftAccountsRepository(_db).openings(),
    history: await DriftTransactionsRepository(_db)
        .ledgerEntries(from: DateTime.utc(1970), to: DateTime.utc(9999)),
    categories: {
      for (final c in await _db.select(_db.categories).get())
        c.id: (key: c.key, type: c.type),
    },
  );

  /// The entries the records call for now, not yet stored.
  Future<List<JournalEntry>> expected() async {
    final r = await _records();
    return postJournal(
      accounts: r.accounts,
      history: r.history,
      categories: r.categories,
    );
  }

  /// Brings the journal in line with the records. See [JournalRepository].
  Future<JournalSync> sync() => _db.transaction(() async {
    final wanted = await expected();
    final rates = {
      for (final t in await (_db.select(
        _db.transactions,
      )..where((t) => t.fxRateMicros.isNotNull())).get())
        t.id: t.fxRateMicros!,
    };
    int? rateOf(JournalEntry e) =>
        e.source == JournalSource.transaction ? rates[e.sourceId] : null;

    final live = await _live();
    final byKey = <(JournalSource, int), List<_Stored>>{};
    for (final s in live) {
      (byKey[(s.row.sourceKind, s.row.sourceId)] ??= []).add(s);
    }
    var posted = 0;
    var reversed = 0;
    final now = _clock();
    for (final e in wanted) {
      final shape = _shape(e.at, e.memo, [
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
  });

  /// Entries that are neither reversed nor reversals, with their postings.
  Future<List<_Stored>> _live() async {
    final j = _db.journalEntries;
    final rows = await _db
        .customSelect(
          'SELECT * FROM journal_entries WHERE reverses IS NULL AND id NOT IN '
          '(SELECT reverses FROM journal_entries WHERE reverses IS NOT NULL)',
          readsFrom: {j},
        )
        .map((row) => j.map(row.data))
        .get();
    final lines = <int, List<Posting>>{};
    for (final p in await _db.select(_db.postings).get()) {
      (lines[p.entryId] ??= []).add(p);
    }
    return [
      for (final row in rows)
        _Stored(
          row,
          lines[row.id] ?? const [],
          _shape(row.occurredAt, row.memo, [
            for (final p in lines[row.id] ?? const <Posting>[])
              (p.account, p.amountMinor, p.currency),
          ], (lines[row.id] ?? const <Posting>[]).firstOrNull?.rateMicros),
        ),
    ];
  }

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

  /// Accounts whose stored journal balance just before [at] is not what
  /// the balance code ([balanceAt], and [fulizaOwedAt] for Fuliza owed)
  /// shows from the same records.
  Future<List<JournalMismatch>> reconcile({required DateTime at}) async {
    final r = await _records();
    final stored = await balances(at: at);
    final out = <JournalMismatch>[];
    for (final a in r.accounts) {
      void check(BookAccount account, int records) {
        final journal = stored[(account, a.currency)] ?? 0;
        if (journal != records) {
          out.add(
            JournalMismatch(
              account: account,
              currency: a.currency,
              journalMinor: journal,
              recordsMinor: records,
            ),
          );
        }
      }

      check(BookAccount.money(a.id), balanceAt(a, r.history, at: at));
      if (a.canOweFuliza) {
        check(BookAccount.fulizaOwed(a.id), fulizaOwedAt(a, r.history, at: at));
      }
    }
    return out;
  }

  /// Builds the journal from the records after the upgrade that added it,
  /// and logs any account that does not reconcile. A failure leaves the
  /// journal to the next [sync]: nothing reads it yet, so the space still
  /// opens.
  static Future<void> backfill(AppDatabase db) async {
    try {
      final journal = JournalRepository(db);
      await journal.sync();
      final off = await journal.reconcile(
        at: DateTime.now().add(const Duration(seconds: 1)),
      );
      if (off.isNotEmpty && kDebugMode) {
        debugPrint('Journal accounts that do not reconcile: $off');
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Building the journal failed: $error');
    }
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
/// rate and postings in a fixed order.
String _shape(
  DateTime at,
  String? memo,
  List<(String, int, String)> lines,
  int? rate,
) {
  final sorted = [for (final (a, m, c) in lines) '$a=$m $c']..sort();
  return '${at.millisecondsSinceEpoch ~/ 1000}|${memo ?? ''}|${rate ?? ''}|'
      '${sorted.join(',')}';
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
  /// must wait for app lock: the first change after it opens syncs
  /// everything, including what was written while no keeper followed, such
  /// as from another space's screens.
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
        // Best effort: nothing reads the journal yet, and the next change
        // syncs everything again.
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
