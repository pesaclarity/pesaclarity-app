import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/plan/upcoming_bills.dart';
import '../../../domain/time/calendar.dart';

/// Unpaid bills due in the next two weeks, for Coming up on Home.
final upcomingBillsProvider = FutureProvider<List<UpcomingBill>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final month = today.yearMonth;
  final plans = ref.watch(planRepositoryProvider);
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: month.startInstant, to: month.next.endInstant);
  return upcomingBills(
    thisMonth: await plans.monthPlan(month),
    nextMonth: await plans.monthPlan(month.next),
    entries: entries,
    today: today,
  );
});
