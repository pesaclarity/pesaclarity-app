// The journal is append-only (decision 0018): an entry or a posting, once
// stored, is never edited or removed. These helpers read every stored row
// so a test can check that between any two moments.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';

/// Every stored journal entry and posting, by id, as text.
typedef JournalRows = ({Map<int, String> entries, Map<int, String> postings});

Future<JournalRows> journalRows(AppDatabase db) async => (
  entries: {
    for (final e in await db.select(db.journalEntries).get()) e.id: '$e',
  },
  postings: {for (final p in await db.select(db.postings).get()) p.id: '$p'},
);

/// Checks that every row of [before] is in [after] as it was, and that
/// what [after] added came after it.
void expectOnlyAppended(JournalRows before, JournalRows after) {
  void check(Map<int, String> was, Map<int, String> now, String what) {
    for (final MapEntry(key: id, value: row) in was.entries) {
      expect(now[id], row, reason: '$what $id was edited or removed');
    }
    final last = was.keys.fold(0, (a, b) => a > b ? a : b);
    for (final id in now.keys) {
      if (!was.containsKey(id)) {
        expect(id, greaterThan(last), reason: '$what $id reuses an old id');
      }
    }
  }

  check(before.entries, after.entries, 'entry');
  check(before.postings, after.postings, 'posting');
}

/// Follows one space's journal through a test: each [check] syncs it, then
/// checks nothing stored before was edited or removed, that every entry
/// sums to zero in each currency, and that a reversal cancels exactly the
/// entry it reverses.
class JournalLog {
  JournalLog(this.db, this.journal);

  final AppDatabase db;
  final JournalRepository journal;
  JournalRows _last = (entries: const {}, postings: const {});

  Future<void> check() async {
    await journal.sync();
    final now = await journalRows(db);
    expectOnlyAppended(_last, now);
    _last = now;
    expect(await journal.unbalanced(), isEmpty);

    final postings = <int, Map<String, int>>{};
    for (final p in await db.select(db.postings).get()) {
      final lines = postings[p.entryId] ??= {};
      final key = '${p.account} ${p.currency}';
      lines[key] = (lines[key] ?? 0) + p.amountMinor;
    }
    final entries = {
      for (final e in await db.select(db.journalEntries).get()) e.id: e,
    };
    final reversed = <int>{};
    for (final e in entries.values) {
      final target = e.reverses;
      if (target == null) continue;
      expect(reversed.add(target), isTrue, reason: '$target reversed twice');
      final original = entries[target]!;
      expect(original.reverses, isNull, reason: 'a reversal was reversed');
      expect(e.occurredAt, original.occurredAt);
      expect(e.sourceKind, original.sourceKind);
      expect(e.sourceId, original.sourceId);
      expect(postings[e.id] ?? const {}, {
        for (final MapEntry(:key, :value)
            in (postings[target] ?? const <String, int>{}).entries)
          key: -value,
      }, reason: 'the reversal of $target');
    }
  }
}
