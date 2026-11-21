import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../application/onboarding_controller.dart';

/// A setup step's main button: [label], with a spinner while [busy].
///
/// When the last try failed, [problem] says so in plain words above it and
/// the button reads Try again, so a step never sits behind a grey button
/// with no word of why.
class SetupAction extends StatelessWidget {
  const SetupAction({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.problem,
    this.identifier,
    super.key,
  });

  final String label;

  /// Null only while nothing can be done yet, such as before a choice.
  final VoidCallback? onPressed;
  final bool busy;
  final String? problem;

  /// The id the UI flows tap it by.
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = this.problem;
    final text = problem == null ? label : 'Try again';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              // Read out when it appears.
              liveRegion: true,
              child: Text(
                problem,
                key: const Key('setup-problem'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
        // Merged so the id lands on the node with the enabled state.
        MergeSemantics(
          child: Semantics(
            identifier: identifier,
            child: FilledButton(
              onPressed: busy ? null : onPressed,
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            semanticsLabel: 'Saving',
                            valueColor: AlwaysStoppedAnimation(
                              PesaColors.of(context).textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(child: Text(text)),
                      ],
                    )
                  : Text(text),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ends setup, so Home opens. When that cannot be saved it says so, with
/// Try again, rather than leaving the button doing nothing.
Future<void> finishSetup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(onboardingControllerProvider.notifier).complete();
  } on Object catch (error) {
    debugPrint('Setup could not be finished: $error');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Setup could not be finished.'),
          // Stays until tapped or replaced: the person has to act on it.
          persist: true,
          action: SnackBarAction(
            label: 'Try again',
            onPressed: () {
              if (context.mounted) finishSetup(context, ref);
            },
          ),
        ),
      );
  }
}
