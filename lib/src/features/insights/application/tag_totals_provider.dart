import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/tags/tag_totals.dart';
import '../../../domain/time/calendar.dart';
import '../../payees/application/payee_providers.dart';

/// This month's totals per tag, by tag id, for Insights. Recomputed when
/// tags are added to or removed from transactions.
final tagTotalsThisMonthProvider = FutureProvider<Map<int, TagSummary>>((
  ref,
) async {
  await ref.watch(tagUsageProvider.future);
  final month = CalendarDate.nairobi(ref.watch(clockProvider)()).yearMonth;
  final from = month.startInstant;
  final to = month.endInstant;
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: from, to: to);
  return tagTotals(entries, from: from, to: to);
});
