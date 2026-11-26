import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/fuliza_tracking.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/home/home_period.dart';
import '../../../domain/time/calendar.dart';
import '../../activity/application/activity_providers.dart';
import '../../income/application/income_providers.dart';
import '../../settings/application/week_start_provider.dart';

/// Days before a period's first day that are read too, so Fuliza
/// repayments in it find their draws.
const _lookBackDays = 31;

/// A period's money in and out and its last days, from the shared money
/// rules and the space's journal, as Activity counts them.
final homePeriodViewProvider =
    FutureProvider.family<HomePeriodView, HomePeriod>(_viewOf);

/// Home's money block: since the last payday when there is a regular
/// income (as safe to spend plans until the next one), otherwise this
/// calendar month.
final homeSincePaydayViewProvider = FutureProvider<HomePeriodView>((ref) async {
  final payday = await ref.watch(paydayProvider.future);
  return _viewOf(ref, HomePeriod.thisMonth, payday: payday?.last);
});

Future<HomePeriodView> _viewOf(
  Ref ref,
  HomePeriod period, {
  CalendarDate? payday,
}) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final weekStartsOn = ref.watch(weekStartsOnProvider);
  final span = payday != null && !payday.isAfter(today)
      ? DateSpan(payday, today)
      : period.spanOn(today, weekStartsOn: weekStartsOn);
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(
        from: span.first.addDays(-_lookBackDays).startInstant,
        to: span.last.addDays(1).startInstant,
      );
  final journal = await ref.watch(activityJournalProvider.future);
  // As Activity: with Fuliza not tracked, its rows leave the days.
  final fulizaRows = ref.watch(fulizaTrackingProvider).value?.shown ?? true;
  return HomePeriodView.of(
    entries,
    period: period,
    today: today,
    weekStartsOn: weekStartsOn,
    journal: journal,
    anyRecords: await ref.watch(_anyRecordsProvider.future),
    listed: fulizaRows ? null : (e) => !isFulizaKind(e.kind),
    payday: payday,
  );
}

/// Whether the open space holds any transaction at all: Home shows how to
/// start until it does.
final _anyRecordsProvider = FutureProvider<bool>((ref) async {
  ref.watch(ledgerChangesProvider);
  final db = ref.watch(appDatabaseProvider);
  final one = await (db.select(db.transactions)..limit(1)).get();
  return one.isNotEmpty;
});
