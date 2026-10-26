import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/sms_capture_providers.dart';

/// Onboarding: explains what reading SMS means before Android asks, then
/// shows the 90-day scan.
class SmsScanScreen extends ConsumerWidget {
  const SmsScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smsScanControllerProvider);
    final controller = ref.read(smsScanControllerProvider.notifier);
    void finish() => ref.read(onboardingControllerProvider.notifier).complete();
    final busy =
        state.stage == SmsScanStage.asking ||
        state.stage == SmsScanStage.scanning;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleSmsScan,
          child: const Text('Your messages'),
        ),
        automaticallyImplyLeading: !busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: switch (state.stage) {
            SmsScanStage.explain || SmsScanStage.asking => [
              const _Explanation(),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : controller.allowAndScan,
                child: const Text('Allow access to messages'),
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: SemanticIds.smsScanNotNow,
                child: TextButton(
                  onPressed: busy ? null : finish,
                  child: const Text('Not now'),
                ),
              ),
            ],
            SmsScanStage.scanning => [
              const _Heading('Reading your messages'),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: state.total == 0 ? null : state.done / state.total,
                semanticsLabel: 'Scan progress',
              ),
              const SizedBox(height: 12),
              _Body(
                state.total == 0
                    ? 'Looking for messages from your accounts.'
                    : 'Read ${state.done} of ${state.total} messages.',
              ),
            ],
            SmsScanStage.finished => [
              _Heading(_foundText(state.summary.added)),
              const SizedBox(height: 8),
              _Body(
                state.summary.forReview == 0
                    ? 'New messages from your accounts will be added as '
                          'they arrive.'
                    : '${_messages(state.summary.forReview)} could not be '
                          'read yet. They wait, encrypted on this phone, '
                          'until you check them.',
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: finish, child: const Text('Continue')),
            ],
            SmsScanStage.denied => [
              const _Heading('Messages not shared'),
              const SizedBox(height: 8),
              const _Body(
                'Without access to messages, Pesa Clarity cannot see your '
                'M-Pesa and bank transactions. You can still add them by '
                'hand or from statements.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.allowAndScan,
                child: const Text('Ask again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: finish,
                child: const Text('Continue without messages'),
              ),
            ],
            SmsScanStage.blocked => [
              const _Heading('Messages are switched off'),
              const SizedBox(height: 8),
              const _Body(
                'Android will not ask again. To let Pesa Clarity read your '
                'account messages, open settings, choose Permissions, then '
                'SMS, and allow it.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.openSettings,
                child: const Text('Open settings'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: controller.checkAgain,
                child: const Text('I have allowed it'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: finish,
                child: const Text('Continue without messages'),
              ),
            ],
            SmsScanStage.unavailable => [
              const _Heading('No messages on this device'),
              const SizedBox(height: 8),
              const _Body(
                'This device cannot share its SMS. You can add transactions '
                'by hand or from statements.',
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: finish, child: const Text('Continue')),
            ],
            SmsScanStage.failed => [
              const _Heading('The scan stopped'),
              const SizedBox(height: 8),
              const _Body(
                'Something went wrong while reading your messages. Nothing '
                'was lost; try again.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.allowAndScan,
                child: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: finish,
                child: const Text('Continue without messages'),
              ),
            ],
          },
        ),
      ),
    );
  }
}

String _messages(int n) => n == 1 ? '1 message' : '$n messages';

String _foundText(int added) => switch (added) {
  0 => 'No transactions found yet',
  1 => 'Found 1 transaction',
  _ => 'Found $added transactions',
};

class _Explanation extends StatelessWidget {
  const _Explanation();

  static const _points = [
    'Only messages from the accounts you ticked are read. Every other '
        'message, including your personal chats, is ignored.',
    'We look back 90 days, then add new messages as they arrive.',
    'From each message we keep the amount, date, fee and who you paid. The '
        'message text is then thrown away.',
    'A message we cannot read yet is kept, encrypted on this phone, until '
        'you check it, then deleted.',
    'Nothing leaves your phone.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Let Pesa Clarity read your account messages'),
        const SizedBox(height: 8),
        const _Body(
          'Android will ask whether Pesa Clarity may read and receive SMS. '
          'This is what that means:',
        ),
        const SizedBox(height: 16),
        for (final point in _points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(child: Text(point, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: PesaColors.of(context).textMuted),
  );
}
