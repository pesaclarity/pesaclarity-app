import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/flavor.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';

/// Onboarding: the promise up front, then sign-up or no account at all.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final flavor = ref.watch(appFlavorProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Semantics(
              identifier: SemanticIds.titleWelcome,
              child: Text('Pesa Clarity', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 32),
            Text(
              'Your money, made clear, without giving your data away.',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Pesa Clarity reads your M-Pesa and bank messages on this phone '
              'and turns them into a daily plan. Nothing about your money '
              'leaves the phone.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 40),
            // TODO(auth): phone number with SMS code.
            Semantics(
              identifier: SemanticIds.onboardingGetStarted,
              child: FilledButton(
                onPressed: () => context.go(AppRoutes.onboardingAccounts),
                child: const Text('Get started'),
              ),
            ),
            if (flavor.allowsGoogleServices) ...[
              const SizedBox(height: 12),
              // TODO(auth): Google sign-in, Play builds only.
              const OutlinedButton(
                onPressed: null,
                child: Text('Continue with Google'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go(AppRoutes.onboardingAccounts),
              child: const Text('Use without an account'),
            ),
          ],
        ),
      ),
    );
  }
}
