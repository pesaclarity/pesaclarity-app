import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/presentation/sign_in_panel.dart';
import '../../privacy/presentation/policy_screen.dart';

/// Onboarding: the promise up front, then sign-up or no account at all.
///
/// Both paths continue to My accounts; signing in can also happen later
/// from Profile.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    void continueOnboarding() => context.go(AppRoutes.onboardingAccounts);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
            child: ConstrainedBox(
              // Keeps the terms at the bottom on tall screens.
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 64).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _AppMark(),
                            const SizedBox(height: 14),
                            Semantics(
                              identifier: SemanticIds.titleWelcome,
                              header: true,
                              child: Text(
                                'Know what you can spend today.',
                                style: theme.textTheme.headlineLarge!.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontVariations: const [
                                    FontVariation.weight(700),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Free forever. Your money data stays on your '
                              'phone.',
                              style: theme.textTheme.bodyLarge!.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SignInPanel(onSignedIn: continueOnboarding),
                      const SizedBox(height: 12),
                      Semantics(
                        identifier: SemanticIds.onboardingGetStarted,
                        child: TextButton(
                          onPressed: continueOnboarding,
                          child: const Text('Get started'),
                        ),
                      ),
                      Text(
                        'Use without an account. You can sign in later from '
                        'Profile.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                    child: _PrivacyNote(
                      color: colors.textMuted,
                      link: colors.link,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Pesa Clarity',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'P',
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation.weight(700)],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.color, required this.link});

  final Color color;
  final Color link;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall!.copyWith(color: color);
    return Column(
      children: [
        Text(
          'An account is only used for sign-in and backups.',
          textAlign: TextAlign.center,
          style: base,
        ),
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const PolicyScreen())),
          style: TextButton.styleFrom(
            foregroundColor: link,
            textStyle: base.copyWith(decoration: TextDecoration.underline),
          ),
          child: const Text('Read our privacy policy'),
        ),
      ],
    );
  }
}
