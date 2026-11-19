import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/accessibility.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/crash_reports.dart';

/// Each choice's name and what it does, as the approved mockup words them.
const crashChoiceLabels = {
  CrashReportChoice.ask: (
    'Ask each time',
    'Show me the report first. The default',
  ),
  CrashReportChoice.always: ('Always send', 'Send it without asking'),
  CrashReportChoice.never: ('Never send', 'Delete it without asking'),
};

/// "Crash reports" from Privacy: Ask each time, Always send or Never send
/// (ADR 0024). The choice is saved on Done.
class CrashChoiceSheet extends ConsumerStatefulWidget {
  const CrashChoiceSheet({super.key});

  static const title = 'Crash reports';
  static const body =
      'When the app closes because of a fault, it can send us a short '
      'report on the next start. Never your data.';
  static const done = 'Done';

  @override
  ConsumerState<CrashChoiceSheet> createState() => _CrashChoiceSheetState();
}

class _CrashChoiceSheetState extends ConsumerState<CrashChoiceSheet> {
  CrashReportChoice? _choice;

  Future<void> _done() async {
    final choice = _choice;
    if (choice != null) {
      await ref.read(crashReportChoiceProvider.notifier).choose(choice);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _choice ?? ref.watch(crashReportChoiceProvider).value;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Layout.gutter,
          8,
          Layout.gutter,
          Layout.screenBottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                CrashChoiceSheet.title,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CrashChoiceSheet.body,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
            const SizedBox(height: Layout.titleGap),
            RadioGroup<CrashReportChoice>(
              groupValue: selected,
              onChanged: (value) => setState(() => _choice = value),
              child: Column(
                children: [
                  for (final choice in CrashReportChoice.values)
                    RadioListTile<CrashReportChoice>(
                      value: choice,
                      title: Text(crashChoiceLabels[choice]!.$1),
                      subtitle: Text(crashChoiceLabels[choice]!.$2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Layout.titleGap),
            FilledButton(
              onPressed: _done,
              child: const Text(CrashChoiceSheet.done),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCrashChoiceSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: reduceMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => const CrashChoiceSheet(),
    );
