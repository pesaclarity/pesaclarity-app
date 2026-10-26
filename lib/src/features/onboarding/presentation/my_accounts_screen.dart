import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/feature_placeholder.dart';
import '../application/onboarding_controller.dart';

/// Onboarding: tick the institutions whose messages the app should read.
class MyAccountsScreen extends ConsumerWidget {
  const MyAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('My accounts')),
      body: FeaturePlaceholder(
        question: 'Which accounts do you use?',
        contents: const [
          'Tick the institutions you transact with: M-Pesa, I&M, KCB, '
              'Equity, Airtel Money and more',
          'Each tick turns on that institution\'s parser pack; no logins, '
              'no passwords',
          'The scan of the last 90 days leads to your first insight in '
              'about a minute',
        ],
        actions: [
          FilledButton(
            // TODO(onboarding): request SMS permission and start the scan.
            onPressed: () =>
                ref.read(onboardingControllerProvider.notifier).complete(),
            child: const Text('Start the 90-day scan'),
          ),
        ],
      ),
    );
  }
}
