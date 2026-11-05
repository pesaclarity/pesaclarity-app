import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/hours_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/time/calendar.dart';
import '../../people/application/people_providers.dart';

/// Hours logged in the week starting on [from], a Monday.
final weekHoursProvider = FutureProvider.family<WeekHours, CalendarDate>((
  ref,
  from,
) async {
  ref.watch(ledgerChangesProvider);
  final entries = await ref
      .watch(hoursRepositoryProvider)
      .between(from, from.addDays(7));
  return WeekHours(from, entries);
});

/// Billable hours not on an invoice yet.
final unbilledHoursProvider = FutureProvider<List<HourEntry>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(hoursRepositoryProvider).unbilled();
});

/// Clients to suggest when logging, with their projects: those with hours
/// first, then customers.
final hourClientsProvider = FutureProvider<Map<String, List<String>>>((
  ref,
) async {
  ref.watch(ledgerChangesProvider);
  final logged = await ref.watch(hoursRepositoryProvider).clientsAndProjects();
  final customers = await ref.watch(customersProvider.future);
  return {
    ...logged,
    for (final c in customers)
      if (!logged.keys.any((k) => k.toLowerCase() == c.name.toLowerCase()))
        c.name: const <String>[],
  };
});
