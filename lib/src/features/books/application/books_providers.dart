import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/books/books.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/time/calendar.dart';
import '../../payees/application/payee_providers.dart';
import '../../spaces/application/spaces_providers.dart';

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
  final sales = categories.where((c) => c.key == salesCategoryKey).firstOrNull;
  return Books.of(
    entries,
    accounts: accounts,
    categories: {for (final c in categories) c.id: (key: c.key, type: c.type)},
    credits: sales == null
        ? const []
        : await ref
              .watch(salesRepositoryProvider)
              .creditSales(salesCategoryId: sales.id),
    purchases: await ref
        .watch(quickRecordsRepositoryProvider)
        .creditPurchases(),
    // Only a business keeps customers and suppliers in its books.
    owedBefore: ref.watch(activeSpaceProvider).kind == SpaceKind.business
        ? await ref
              .watch(quickRecordsRepositoryProvider)
              .owedBefore(suppliersAt: _booksStart(accounts))
        : const [],
  );
});

/// When the books start: the earliest account opening.
DateTime _booksStart(Iterable<AccountOpening> accounts) => accounts.isEmpty
    ? DateTime.utc(1970)
    : accounts
          .map((a) => a.openingDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
