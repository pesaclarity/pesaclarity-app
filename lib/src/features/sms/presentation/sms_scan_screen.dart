import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/links.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../application/sms_capture_providers.dart';
import 'explain_text.dart';

/// Onboarding: explains what reading SMS means before Android asks, then
/// shows the first scan.
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
                  child: const Text('Do this later'),
                ),
              ),
            ],
            SmsScanStage.scanning => [
              const ExplainHeading('Reading your messages'),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: state.total == 0 ? null : state.done / state.total,
                semanticsLabel: 'Scan progress',
              ),
              const SizedBox(height: 12),
              ExplainBody(
                state.total == 0
                    ? 'Looking for messages from your accounts.'
                    : 'Read ${state.done} of ${state.total} messages.',
              ),
            ],
            SmsScanStage.finished => [
              ExplainHeading(_foundText(state.summary.added)),
              const SizedBox(height: 8),
              ExplainBody(
                state.summary.forReview == 0
                    ? 'New messages from your accounts will be added as '
                          'they arrive.'
                    : '${_messages(state.summary.forReview)} could not be '
                          'read yet. They wait, encrypted on this phone, '
                          'until you check them.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                // The first insight needs transactions to add up.
                onPressed: state.summary.added > 0
                    ? () => context.go(AppRoutes.onboardingFirstInsight)
                    : finish,
                child: const Text('Continue'),
              ),
            ],
            SmsScanStage.denied => [
              const ExplainHeading('Messages not shared'),
              const SizedBox(height: 8),
              const ExplainBody(
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
              const ExplainHeading('Allow messages in Settings'),
              const SizedBox(height: 8),
              const ExplainBody(
                'Android needs you to switch this on yourself. It takes a '
                'minute:',
              ),
              const SizedBox(height: 12),
              const _Steps(blockedSteps),
              const SizedBox(height: 8),
              const ExplainBody(
                'On some phones the ⋮ menu is at the bottom of App info.',
              ),
              const SizedBox(height: 16),
              const ExplainHeading('Xiaomi, Redmi or POCO?'),
              const SizedBox(height: 8),
              const ExplainBody(
                'If SMS says App was denied access and ⋮ has no Allow '
                'restricted settings, install Pesa Clarity through Obtainium, '
                'a free app store. Apps it installs can read SMS.',
              ),
              TextButton(
                key: const Key('sms-install-guide'),
                onPressed: () => launchUrl(
                  Uri.parse(installGuideUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('How to install with Obtainium'),
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
              const ExplainHeading('No messages on this device'),
              const SizedBox(height: 8),
              const ExplainBody(
                'This device cannot share its SMS. You can add transactions '
                'by hand or from statements.',
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: finish, child: const Text('Continue')),
            ],
            SmsScanStage.failed => [
              const ExplainHeading('The scan stopped'),
              const SizedBox(height: 8),
              const ExplainBody(
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
    'Only messages from the accounts you ticked are read. Your personal '
        'chats stay private.',
    'We read the messages you chose, then add new ones as they arrive.',
    'From each message we keep the amount, date, fee and who you paid. The '
        'message text is then thrown away.',
    'A message we cannot read yet is kept, encrypted on this phone, until '
        'you check it, then deleted.',
    'Everything stays on your phone.',
  ];

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExplainHeading('Let Pesa Clarity read your account messages'),
      SizedBox(height: 8),
      ExplainBody(
        'Android will ask whether Pesa Clarity may read and receive SMS. '
        'This is what that means:',
      ),
      SizedBox(height: 16),
      TickPoints(_points),
    ],
  );
}

/// How to allow SMS once Android has stopped asking, including the
/// restricted setting Android puts on apps installed from a file.
const blockedSteps = [
  'Tap Open settings below. It opens App info for Pesa Clarity.',
  'If SMS says "Restricted setting", tap ⋮ at the top right, then Allow '
      'restricted settings, and confirm with your PIN.',
  'Open Permissions, then SMS, and choose Allow.',
  'Come back here and tap I have allowed it.',
];

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(step, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
