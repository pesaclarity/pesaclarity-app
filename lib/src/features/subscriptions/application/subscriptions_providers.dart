import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/subscriptions_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/subscriptions/subscriptions.dart';
import '../../../domain/time/calendar.dart';

/// Saved subscriptions, tracked and dismissed.
final savedSubscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(subscriptionsRepositoryProvider).watchAll(),
);

/// Tracked subscriptions with their latest charges, their cost, and repeat
/// charges worth tracking. Reads a year back so yearly charges are found.
final subscriptionsOverviewProvider = FutureProvider<SubscriptionsOverview>((
  ref,
) async {
  ref.watch(ledgerChangesProvider);
  final saved = await ref.watch(savedSubscriptionsProvider.future);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: today.yearMonth.addMonths(-13).startInstant,
        to: today.addDays(1).startInstant,
      );
  return SubscriptionsOverview.of(saved: saved, entries: entries, today: today);
});
