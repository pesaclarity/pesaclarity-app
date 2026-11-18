import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../domain/ledger/ledger_entry.dart';
import 'journal_repository.dart';
import 'transactions_repository.dart';

/// The start and end of the whole ledger, as the journal reads it.
final _everFrom = DateTime.utc(1970);
final _everTo = DateTime.utc(9999);

/// Every ledger entry of the open space at one ledger generation (see
/// `JournalRepository.generation`), read through one repository (which
/// holds the database and the currency converter), oldest first.
///
/// Home's cards and Balances each want years of history after every
/// change; they share this one read, as they share the journal's (see
/// `journalAtGenerationProvider`, whose keep-alive rules this follows).
final ledgerHistoryAtGenerationProvider = FutureProvider.autoDispose
    .family<List<LedgerEntry>, (int, TransactionsRepository)>((ref, key) {
      final (generation, transactions) = key;
      final latest = ref.read(_latestHistoryProvider);
      final link = ref.keepAlive();
      final newest = latest.generation;
      if (newest == null || generation >= newest) {
        final older = latest.link;
        latest
          ..link = link
          ..generation = generation;
        older?.close();
      } else {
        link.close();
      }
      return transactions.ledgerEntries(from: _everFrom, to: _everTo);
    });

class _LatestHistory {
  KeepAliveLink? link;
  int? generation;
}

final _latestHistoryProvider = Provider<_LatestHistory>(
  (ref) => _LatestHistory(),
);

/// The open space's ledger entries with time in `[from, to)`, oldest first,
/// as `TransactionsRepository.ledgerEntries` gives them, cut from the one
/// read of the whole ledger shared per change (see
/// [ledgerHistoryAtGenerationProvider]). Providers that call this watch
/// `ledgerChangesProvider` themselves, as with `readJournal`.
Future<List<LedgerEntry>> readLedgerHistory(
  Ref ref, {
  required DateTime from,
  required DateTime to,
}) async {
  final transactions = ref.watch(transactionsRepositoryProvider);
  if (from.isBefore(_everFrom) || to.isAfter(_everTo)) {
    return transactions.ledgerEntries(from: from, to: to);
  }
  final generation = ref.watch(journalRepositoryProvider).generation;
  final all = await ref.watch(
    ledgerHistoryAtGenerationProvider((generation, transactions)).future,
  );
  return entriesBetween(all, from: from, to: to);
}

/// The entries of [all] (oldest first) with time in `[from, to)`, compared
/// as the database compares them: to the whole second, as stored.
List<LedgerEntry> entriesBetween(
  List<LedgerEntry> all, {
  required DateTime from,
  required DateTime to,
}) {
  int seconds(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
  // The first entry at or after [at], by binary search.
  int firstFrom(int at) {
    var lo = 0;
    var hi = all.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (seconds(all[mid].occurredAt) < at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  final start = firstFrom(seconds(from));
  final end = firstFrom(seconds(to));
  return end <= start ? <LedgerEntry>[] : all.sublist(start, end);
}
