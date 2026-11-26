import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/budget/budget_alerts.dart';
import '../../../domain/goals/goals_aside.dart';
import '../../../domain/habits/week_check_in.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/income/make_it_last.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../accounts/application/mpesa_lines_providers.dart';
import '../../accounts/presentation/line_questions.dart';
import '../../app_status/application/app_status_providers.dart';
import '../../habits/application/habits_providers.dart';
import '../../income/application/income_providers.dart';
import '../../onboarding/application/about_you_providers.dart';
import '../../plan/application/budget_alert_providers.dart';
import '../../review/application/review_providers.dart';
import '../../settings/application/week_start_provider.dart';
import '../../sms/application/read_again.dart';
import '../../spaces/application/restore_check_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../support/application/support_providers.dart';
import '../../support/domain/support.dart';
import 'goal_dips_provider.dart';
import 'home_safe_provider.dart';
import 'not_yet_sorted_provider.dart';

/// Where a thing to sort is listed.
enum SortGroup {
  /// Something is waiting on the person: amber dot.
  needsYou,

  /// Worth a look, not urgent.
  whenYouHaveTime,
}

/// One thing in Things to sort, as Home's row sums it up.
class SortThing {
  const SortThing(this.group, this.summary);

  final SortGroup group;

  /// A few words for Home's row: `3 to check`, `Food at 80%`.
  final String summary;
}

/// The budget alerts that are real problems: a category over its plan.
/// They show on Home on their own, not in Things to sort.
final overBudgetAlertsProvider = Provider<List<BudgetAlert>>(
  (ref) => [
    for (final a
        in ref.watch(budgetAlertsProvider).value ?? const <BudgetAlert>[])
      if (a.level == BudgetAlertLevel.over) a,
  ],
);

/// Budget alerts nearing their plan (from the share set in Profile, 80%
/// by default): listed in Things to sort.
final nearBudgetAlertsProvider = Provider<List<BudgetAlert>>(
  (ref) => [
    for (final a
        in ref.watch(budgetAlertsProvider).value ?? const <BudgetAlert>[])
      if (a.level != BudgetAlertLevel.over) a,
  ],
);

/// Everything Things to sort lists, in the order it lists them, each
/// shown under the same rules as the card it opens. Home shows its row
/// only while this is not empty.
final thingsToSortProvider = Provider<List<SortThing>>((ref) {
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final personal = ref.watch(activeSpaceProvider).kind == SpaceKind.personal;
  const needs = SortGroup.needsYou;
  const later = SortGroup.whenYouHaveTime;
  final things = <SortThing>[];

  // Needs you.
  final sorted = ref.watch(notYetSortedProvider).value;
  if (sorted != null && !sorted.isEmpty) {
    final count = sorted.messagesToCheck + sorted.peopleNotNamed;
    things.add(SortThing(needs, '$count not yet sorted'));
  }
  for (final alert in ref.watch(nearBudgetAlertsProvider)) {
    things.add(SortThing(needs, '${alert.name} at ${alert.usedPercent}%'));
  }
  for (final dip in ref.watch(goalDipsProvider).value ?? const <GoalDip>[]) {
    if (!dip.seen) things.add(SortThing(needs, '${dip.goal.name} dipped'));
  }
  if (ref.watch(oneSidedProvider).value != null) {
    things.add(const SortThing(needs, 'a restore check'));
  }
  if (ref.watch(readsMpesaHereProvider).value ?? false) {
    final lines = ref.watch(mpesaLinesProvider).value;
    if (lines != null) {
      final which = ref.watch(whichLineItemsProvider).value ?? const [];
      if (lines.offersSplit && !lines.offerHidden) {
        things.add(const SortThing(needs, 'two M-Pesa lines'));
      }
      if (which.isNotEmpty) things.add(const SortThing(needs, 'which line'));
      if (lines.skipNote == SkipNote.due) {
        things.add(const SortThing(later, 'a skipped line'));
      }
      if (lines.nextSimQuestion != null) {
        things.add(const SortThing(needs, 'a new SIM'));
      }
    }
  }

  // When you have time.
  final habits = ref.watch(habitSettingsProvider).value;
  final week = ref.watch(weekCheckInProvider).value;
  if (personal &&
      habits != null &&
      habits.sundayCheckIn &&
      week != null &&
      isCheckInDay(week.end, ref.watch(weekStartsOnProvider))) {
    things.add(const SortThing(later, 'weekly check-in'));
  }
  final noSpend = ref.watch(noSpendDaysProvider).value;
  if (personal &&
      habits != null &&
      habits.noSpendOnHome &&
      noSpend != null &&
      noSpend.weekCount > 0) {
    things.add(const SortThing(later, 'no-spend days'));
  }
  if (ref.watch(readAgainNoticeProvider).value != null) {
    things.add(const SortThing(later, 'read again'));
  }
  final answers = ref.watch(aboutYouProvider).value;
  if (ref.watch(activeSpaceIdProvider) == personalSpaceId &&
      answers != null &&
      answers.homeOfferOn(today)) {
    things.add(const SortThing(later, 'about you'));
  }
  if (_supportShows(ref)) things.add(const SortThing(later, 'support'));
  final untilNext = ref.watch(homeSafeProvider).untilNext;
  if (untilNext != null && _makeItLastShows(ref, today)) {
    things.add(const SortThing(later, 'make it last'));
  }
  final sources =
      ref.watch(incomeSourcesProvider).value ?? const IncomeSources({});
  if (untilNext != null &&
      sources.irregular &&
      ref.watch(weekByWeekProvider).value != null) {
    things.add(const SortThing(later, 'this week'));
  }
  final status = ref.watch(appStatusProvider).value;
  if (status != null && status.blocking == null) {
    for (final _ in status.cards) {
      things.add(const SortThing(later, 'news'));
    }
  }
  return things;
});

/// Whether the support card shows (see [supportCardTime]).
bool _supportShows(Ref ref) {
  if (ref.watch(supportConfigProvider) == null) return false;
  final state = ref.watch(supportStateProvider).value;
  final gifts = ref.watch(giftsProvider).value;
  if (state == null || gifts == null) return false;
  return supportCardTime(
        state: state,
        now: ref.watch(clockProvider)(),
        moneyTight: ref.watch(homeMoneyTightProvider),
        lastGiftAt: gifts.firstOrNull?.at,
      ) !=
      SupportCardTime.hidden;
}

/// Whether Make it last is offered for the latest money in.
bool _makeItLastShows(Ref ref, CalendarDate today) {
  final arrival = ref.watch(latestArrivalProvider).value;
  final pin = ref.watch(makeItLastProvider).value;
  return arrival != null &&
      today.daysUntil(arrival.date) >= -makeItLastOfferDays &&
      !(pin != null && pin.arrivalId == arrival.id);
}

/// Home's row under the count: `3 not yet sorted, Food at 80% and 2 more`.
String sortSummary(List<SortThing> things) {
  if (things.isEmpty) return '';
  final first = _cap(things.first.summary);
  if (things.length == 1) return first;
  if (things.length == 2) return '$first and ${things[1].summary}';
  return '$first, ${things[1].summary} and ${things.length - 2} more';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
