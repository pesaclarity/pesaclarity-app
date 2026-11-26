import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/presentation/line_questions.dart';
import '../../app_status/presentation/app_notice_cards.dart';
import '../../habits/presentation/habits_home_cards.dart';
import '../../onboarding/presentation/about_you_cards.dart';
import '../../plan/presentation/budget_alert_cards.dart';
import '../../sms/presentation/read_again_home_card.dart';
import '../../spaces/presentation/restore_check_card.dart';
import '../../support/presentation/support_card.dart';
import '../application/home_safe_provider.dart';
import '../application/things_to_sort_provider.dart';
import 'goal_dip_cards.dart';
import 'home_cards.dart';
import 'not_yet_sorted_card.dart';

/// Everything that wants a moment, in one list, opened from Home's
/// "Things to sort" row: what needs the person first, then what can wait.
/// Each is the card Home used to show, under the same rules, so done
/// items leave the list as they left Home.
class ThingsToSortScreen extends ConsumerWidget {
  const ThingsToSortScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final things = ref.watch(thingsToSortProvider);
    final needs = things.any((t) => t.group == SortGroup.needsYou);
    final later = things.any((t) => t.group == SortGroup.whenYouHaveTime);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final untilNext = ref.watch(homeSafeProvider).untilNext;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Things to sort'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: AmountsHiddenScope(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Everything that wants a moment from you, in one place. Done '
              'items leave the list.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
            if (things.isEmpty) ...[
              const SizedBox(height: 16),
              const EmptyNote('Nothing to sort right now.'),
            ],
            if (needs) const SectionLabel('Needs you'),
            const NotYetSortedCard(),
            for (final alert in ref.watch(nearBudgetAlertsProvider))
              BudgetAlertCard(
                alert,
                key: Key('sort-budget-alert-${alert.categoryId}'),
                inPlan: false,
                onTap: () => context.go(AppRoutes.plan),
              ),
            const GoalDipCards(),
            const RestoreCheckCard(),
            const LineQuestionRows(),
            if (later) const SectionLabel('When you have time'),
            const SundayCheckInCard(),
            const NoSpendCard(),
            const ReadAgainHomeCard(),
            const AboutYouHomeCard(),
            SupportHomeCard(moneyTight: ref.watch(homeMoneyTightProvider)),
            if (untilNext != null) ...[
              MakeItLastCard(untilNext, today: today),
              const WeekByWeekCard(),
            ],
            const AppNoticeCards(),
          ],
        ),
      ),
    );
  }
}
