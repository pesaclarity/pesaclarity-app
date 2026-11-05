import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/books/cash_book.dart';
import '../../../domain/time/calendar.dart';

/// Days the Money tab shows at first; "Show older" adds as many again.
const cashBookPageDays = 14;

/// The open space's cash book, with days from [from] to today, following
/// every change to its records.
final cashBookProvider = FutureProvider.family<CashBook, CalendarDate>((
  ref,
  from,
) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final to = today.addDays(1).startInstant;
  final accounts = await ref.watch(accountsRepositoryProvider).openings();
  // Balances count from each account's opening, so all records are read.
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: DateTime.utc(1970), to: to);
  return CashBook.of(
    entries,
    accounts: accounts,
    to: to,
    from: from,
    currency: BaseCurrency.code,
  );
});
