import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../domain/debts/payoff_order.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/time/calendar.dart';

/// Today's payoff plan against minimums only, from this month, in the
/// user's own order when they set one and avalanche otherwise. Null when
/// nothing is owed.
final debtPlanProvider = FutureProvider<PayoffComparison?>((ref) async {
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final repository = ref.watch(debtsRepositoryProvider);
  final debts = await repository.debts(today: today);
  if (debts.every((d) => d.balanceMinor == 0)) return null;
  final order = await repository.customOrder();
  return PayoffComparison.againstMinimums(
    debts,
    PayoffOptions(
      startMonth: today.yearMonth,
      strategy: order.isEmpty
          ? PayoffStrategy.avalanche
          : PayoffStrategy.custom,
      customOrder: order,
    ),
  );
});
