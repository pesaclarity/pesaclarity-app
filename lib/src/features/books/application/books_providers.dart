import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/books/books.dart';
import '../../../domain/time/calendar.dart';
import '../../payees/application/payee_providers.dart';

/// The open space's double-entry books up to today, following every change
/// to its records.
final booksProvider = FutureProvider<Books>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  final to = today.addDays(1).startInstant;
  // Entries before an account's opening still post, and its opening
  // balance absorbs them, so every record is read.
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: DateTime.utc(1970), to: to);
  final categories = await ref.watch(categoriesProvider.future);
  return Books.of(
    entries,
    accounts: accounts,
    categories: {for (final c in categories) c.id: (key: c.key, type: c.type)},
  );
});
