import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/payday_repository.dart';
import '../../../domain/plan/payday.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../application/plan_providers.dart';
import 'plan_screen.dart' show dayLabel;

/// Payday autopilot: the proposed split of this payday as a checklist.
class PaydayScreen extends ConsumerWidget {
  const PaydayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposal = ref.watch(paydayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Payday')),
      body: switch (proposal) {
        AsyncData(value: final p?) => _Checklist(p),
        AsyncData() => const Padding(
          padding: EdgeInsets.symmetric(horizontal: Layout.gutter),
          child: EmptyNote(
            'Your payday checklist shows here when your salary lands, or '
            'on the day Plan expects it.',
          ),
        ),
        AsyncError() => ErrorView(
          'Your payday checklist could not load.',
          onRetry: () => ref.invalidate(paydayProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Checklist extends ConsumerWidget {
  const _Checklist(this.proposal);

  final PaydayProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    String kes(int minor) => shownMoney(context, minor, withCurrency: true);
    final payday = proposal.payday;
    final checklist = proposal.checklist;
    final tasks = checklist.tasks;
    final done = tasks.where((t) => proposal.ticked.contains(t.key)).length;

    final caption = StringBuffer(
      payday.fromMessage
          ? 'Landed by ${dayLabel(payday.date)}. '
          : 'Expected on ${dayLabel(payday.date)}. ',
    );
    if (checklist.shortfallMinor > 0) {
      caption.write(
        'The plan needs ${kes(checklist.shortfallMinor)} more than this. ',
      );
    }
    caption.write('$done of ${tasks.length} done.');

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        8,
        Layout.gutter,
        Layout.screenBottom,
      ),
      children: [
        HeroFigureCard(
          label: 'This payday',
          figure: kes(payday.amountMinor),
          caption: caption.toString(),
        ),
        const SizedBox(height: 16),
        Text(
          'Tick each one off as you pay it or move it.',
          style: theme.textTheme.bodyMedium,
        ),
        for (final kind in PaydayTaskKind.values)
          if (tasks.any((t) => t.kind == kind)) ...[
            SectionTitle(kind.label),
            for (final task in tasks.where((t) => t.kind == kind))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: proposal.ticked.contains(task.key),
                title: Text(task.name),
                subtitle: task.dueDate == null
                    ? null
                    : Text('Due ${dayLabel(task.dueDate!)}'),
                secondary: Text(
                  shownMoney(context, task.amountMinor, withCurrency: false),
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) async {
                  await ref
                      .read(paydayRepositoryProvider)
                      .setTicked(proposal.month, task.key, value ?? false);
                  ref.invalidate(paydayProvider);
                },
              ),
          ],
        const SizedBox(height: 24),
        if (proposal.isComplete)
          Text('All done for this payday.', style: theme.textTheme.titleMedium)
        else if (!proposal.isDismissed)
          OutlinedButton(
            onPressed: () async {
              await ref.read(paydayRepositoryProvider).dismiss(proposal.month);
              ref.invalidate(paydayProvider);
              if (context.mounted) Navigator.of(context).maybePop();
            },
            child: const Text('Hide until next payday'),
          ),
      ],
    );
  }
}
