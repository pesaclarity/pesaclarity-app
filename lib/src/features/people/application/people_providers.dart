import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/lending_repository.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/time/calendar.dart';

/// The open business's customers and what each owes, following every
/// sale and payment.
final customersProvider = FutureProvider<List<CustomerAccount>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  return customersFrom(
    await ref.watch(lendingRepositoryProvider).lent(),
    today: today,
  );
});

/// The suppliers the open business owes, soonest due first.
final suppliersProvider = FutureProvider<List<SupplierAccount>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  return suppliersFrom(
    await ref.watch(debtsRepositoryProvider).debts(today: today),
    today: today,
  );
});

/// Payments to suppliers this month, newest first.
final suppliersPaidThisMonthProvider = FutureProvider<List<PaidRecord>>((
  ref,
) async {
  ref.watch(ledgerChangesProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final month = today.yearMonth;
  return ref
      .watch(quickRecordsRepositoryProvider)
      .paidBetween(
        from: month.firstDay.startInstant,
        to: today.addDays(1).startInstant,
      );
});
