import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../domain/about_you/about_you.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../goals/application/goals_overview_provider.dart';
import '../application/about_you_providers.dart';

/// "Make it yours": the offer of About you's three questions. On the last
/// setup screen, and once more on Home with [onClose].
class MakeItYoursCard extends StatelessWidget {
  const MakeItYoursCard({required this.onAnswer, this.onClose, super.key});

  final VoidCallback onAnswer;

  /// Shown as a close button, for Home's offer.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Make it yours',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    key: const Key('about-offer-close'),
                    tooltip: 'Close',
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: PesaColors.of(context).textMuted,
                    ),
                    onPressed: onClose,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Three quick questions, about a minute. Skip any. Answers stay '
              'on this phone.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('about-offer-answer'),
              onPressed: onAnswer,
              child: const Text('Answer 3 questions'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home: About you offered once more, from the day after setup offered it,
/// until it is answered, taken or closed. Personal only.
class AboutYouHomeCard extends ConsumerWidget {
  const AboutYouHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeSpaceIdProvider) != personalSpaceId) {
      return const SizedBox.shrink();
    }
    final answers = ref.watch(aboutYouProvider).value;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    if (answers == null || !answers.homeOfferOn(today)) {
      return const SizedBox.shrink();
    }
    Future<void> close() async {
      try {
        await ref.read(aboutYouProvider.notifier).closeHomeOffer();
      } on Object catch (error) {
        debugPrint('Home offer could not be closed: $error');
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MakeItYoursCard(
        key: const Key('home-about-you'),
        onClose: close,
        onAnswer: () {
          // Taking the offer is its once more: after it, only Profile.
          close();
          context.push(AppRoutes.aboutYou);
        },
      ),
    );
  }
}

/// Goals: the one goal About you suggests, with Add this goal and Not now.
/// It goes for good after either, or once any goal is added.
class AboutYouGoalOffer extends ConsumerStatefulWidget {
  const AboutYouGoalOffer({super.key});

  @override
  ConsumerState<AboutYouGoalOffer> createState() => _AboutYouGoalOfferState();
}

class _AboutYouGoalOfferState extends ConsumerState<AboutYouGoalOffer> {
  var _busy = false;

  Future<void> _add(GoalSuggestion goal) async {
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final today = CalendarDate.local(ref.read(clockProvider)());
      await ref
          .read(goalsRepositoryProvider)
          .add(
            name: goal.name,
            targetMinor: goal.targetMinor,
            targetDate: CalendarDate(today.year + 1, today.month, today.day),
          );
      await ref.read(aboutYouProvider.notifier).closeGoalOffer();
    } on Object catch (error) {
      debugPrint('The suggested goal could not be added: $error');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('The goal could not be added.')),
          );
      }
      return;
    }
    refreshGoals(container);
    container.invalidate(aboutYouGoalProvider);
  }

  Future<void> _notNow() async {
    setState(() => _busy = true);
    try {
      await ref.read(aboutYouProvider.notifier).closeGoalOffer();
    } on Object catch (error) {
      debugPrint('The suggested goal could not be put off: $error');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) ref.invalidate(aboutYouGoalProvider);
  }

  @override
  Widget build(BuildContext context) {
    final goal = ref.watch(aboutYouGoalProvider).value;
    if (goal == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final target = shownMoney(context, goal.targetMinor);
    final monthly = shownMoney(context, goal.monthlyMinor);
    final size = goal.halfMonth
        ? 'Half a month of spending is about $target.'
        : 'One month of spending is about $target.';
    final text = '${goal.reason} $size $monthly a month gets there in a year.';
    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            key: const Key('goals-about-you'),
            child: Padding(
              padding: const EdgeInsets.all(Layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Start an emergency fund?',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  readAsAmount(
                    text,
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ButtonPair(
                    primary: FilledButton(
                      key: const Key('goals-about-you-add'),
                      onPressed: _busy ? null : () => _add(goal),
                      child: const Text('Add this goal'),
                    ),
                    secondary: OutlinedButton(
                      key: const Key('goals-about-you-not-now'),
                      onPressed: _busy ? null : _notNow,
                      child: const Text('Not now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 0),
            child: Text(
              'One suggestion, from your answers. It goes once you add a goal '
              'or tap Not now.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
