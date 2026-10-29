import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/time/calendar.dart';

/// Days of history Activity loads at first; "Show older" adds as much again.
const activityPageDays = 60;

/// Ledger entries from [from] to today, oldest first, refreshed whenever the
/// ledger changes. Always reaches back to this week's Monday so the weekly
/// totals are whole.
final activityEntriesProvider =
    FutureProvider.family<List<LedgerEntry>, CalendarDate>((ref, from) async {
      ref.watch(ledgerChangesProvider);
      final today = CalendarDate.local(ref.watch(clockProvider)());
      final monday = startOfWeek(today);
      final start = from.isBefore(monday) ? from : monday;
      return ref
          .watch(transactionsRepositoryProvider)
          .ledgerEntries(
            from: start.startInstant,
            to: today.addDays(1).startInstant,
          );
    });

/// Accounts by id, for filters and line labels.
final activityAccountsProvider = StreamProvider<Map<int, Account>>(
  (ref) => ref
      .watch(accountsRepositoryProvider)
      .watchAll()
      .map((list) => {for (final a in list) a.id: a}),
);

/// Categories by id, for line labels and search.
final activityCategoriesProvider = StreamProvider<Map<int, Category>>(
  (ref) => ref
      .watch(categoriesRepositoryProvider)
      .watchAll()
      .map((list) => {for (final c in list) c.id: c}),
);
