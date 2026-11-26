import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/ask/periods.dart';
import '../../../domain/budget/budget_alerts.dart';
import '../../../domain/time/calendar.dart';
import '../../ask/application/ask_providers.dart';
import '../../income/application/income_providers.dart';
import '../../insights/application/insights_providers.dart';
import '../../plan/application/budget_alert_providers.dart';
import '../../plan/application/plan_providers.dart' hide paydayProvider;
import '../domain/slm_facts.dart';

/// The facts for the model, from the open space's records, read on the
/// phone through the same sources Ask and the screens use. Never sent
/// anywhere.
///
/// Everything it needs from `ref` is read before the first `await`: the
/// provider is auto-disposed, so `ref` may be gone by the time a read
/// finishes, and using it then throws. The providers it needs are watched,
/// not read: one with no listener is paused and may never answer. It is
/// also kept alive until it has its answer, so a read with nothing
/// listening still gets one.
final slmFactsProvider = FutureProvider.autoDispose<SlmFacts>((ref) async {
  final link = ref.keepAlive();
  try {
    return await _load(ref);
  } finally {
    // Let it go once the reader has the answer.
    unawaited(Future<void>(link.close));
  }
});

Future<SlmFacts> _load(Ref ref) async {
  final today = CalendarDate.local(ref.read(clockProvider)());
  final data = ref.read(askDataSourceProvider);
  final month = today.yearMonth;
  final paydayRead = ref.watch(paydayProvider.future);
  final namesRead = ref.watch(categoryNamesProvider.future);
  final viewRead = ref.watch(planViewProvider(month).future);
  final planNames = ref.read(planCategoryNamesProvider);
  // Failures surface when each is awaited below, not as unhandled errors.
  for (final read in [paydayRead, namesRead, viewRead]) {
    unawaited(read.then((_) {}, onError: (_) {}));
  }
  final entries = await data.entries(
    month.addMonths(-3).startInstant,
    today.addDays(1).startInstant,
  );

  Future<T?> maybe<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  final payday = await maybe(() => paydayRead);
  final names = await maybe(() => namesRead);
  final balances = await maybe(data.balances) ?? const [];
  final bills = await maybe(data.billsDue) ?? const [];
  final fees = await maybe(() => data.fees(AskPeriod.thisMonth(today)));
  final view = await maybe(() => viewRead);
  final budgets = <SlmBudget>[
    if (view != null)
      for (final c in view.review.categories)
        if (c.plannedMinor > 0 &&
            isBudgetCategory(view.review.plan, c.categoryId))
          SlmBudget(
            planNames[c.categoryId] ?? names?[c.categoryId] ?? 'A category',
            c.plannedMinor,
            c.actualMinor,
          ),
  ];
  return SlmFacts.of(
    SlmFactsInput(
      today: today,
      entries: entries,
      lastPayday: payday?.last,
      categoryNames: names ?? const {},
      balances: [
        for (final b in balances)
          SlmLine(b.name, b.amountMinor, savings: b.savings),
      ],
      bills: [
        for (final b in bills) SlmLine(b.name, b.amountMinor, date: b.date),
      ],
      budgets: budgets,
      feesThisMonthMinor: fees,
    ),
  );
}
