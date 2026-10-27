import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/time/calendar.dart';
import 'debts_overview_provider.dart';

/// Today's payoff plan against minimums only, from this month, with the
/// strategy the person chose on Debts. Null when nothing is owed.
final debtPlanProvider = FutureProvider<PayoffComparison?>((ref) async {
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final repository = ref.watch(debtsRepositoryProvider);
  final debts = await repository.debts(today: today);
  if (debts.every((d) => d.balanceMinor == 0)) return null;
  final preference = await ref.watch(debtPreferenceProvider.future);
  return PayoffComparison.againstMinimums(
    debts,
    preference.options(today.yearMonth),
  );
});
