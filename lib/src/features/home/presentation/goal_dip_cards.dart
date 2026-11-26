import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/goals/goals_aside.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../theme/pesa_colors.dart';
import '../../goals/presentation/goal_dip_sheet.dart';
import '../../goals/presentation/goals_aside_text.dart';
import '../application/goal_dips_provider.dart';

/// "You dipped KES 1,500 into School fees": a gentle card, with an amber
/// dot rather than red, for each goal kept aside that spending has dipped
/// into and the person has not answered yet.
class GoalDipCards extends ConsumerWidget {
  const GoalDipCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dips = [
      for (final dip in ref.watch(goalDipsProvider).value ?? const <GoalDip>[])
        if (!dip.seen) dip,
    ];
    if (dips.isEmpty) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return Column(
      children: [
        for (final dip in dips)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                key: Key('home-goal-dip-${dip.goal.id}'),
                leading: Icon(Icons.circle, size: 10, color: colors.warning),
                minLeadingWidth: 10,
                title: Text(
                  GoalsAsideText.dipped(
                    shownMoney(
                      context,
                      dip.dipMinor,
                      currency: dip.goal.currency,
                      withCurrency: true,
                    ),
                    dip.goal.name,
                  ),
                ),
                subtitle: const Text(GoalsAsideText.dipDetail),
                trailing: Icon(Icons.chevron_right, color: colors.textMuted),
                onTap: () => showGoalDipSheet(context, dip: dip, today: today),
              ),
            ),
          ),
      ],
    );
  }
}
