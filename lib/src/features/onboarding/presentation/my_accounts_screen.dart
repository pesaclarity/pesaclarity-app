import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';

import '../../../theme/pesa_colors.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../accounts/presentation/institution_list.dart';

/// Onboarding: tick the institutions whose messages the app should read.
class MyAccountsScreen extends ConsumerWidget {
  const MyAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hasSelection =
        ref.watch(selectedInstitutionIdsProvider).value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('My accounts')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Which accounts do you use?',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tick the ones you transact with. Pesa Clarity reads only '
              'messages from these senders, on this phone. No logins, no '
              'passwords.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const InstitutionList(control: InstitutionControl.checkbox),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: hasSelection
                  ? () => context.go(AppRoutes.onboardingScan)
                  : null,
              child: const Text('Scan my messages'),
            ),
            const SizedBox(height: 8),
            Text(
              hasSelection
                  ? 'We look back over the last 90 days. You can change '
                        'your accounts any time in Profile.'
                  : 'Tick at least one account to continue.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
