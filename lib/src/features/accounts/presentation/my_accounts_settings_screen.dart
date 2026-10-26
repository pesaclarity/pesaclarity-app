import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../application/my_accounts_providers.dart';
import 'institution_list.dart';

/// Profile > My accounts: switch institutions on or off at any time.
class MyAccountsSettingsScreen extends ConsumerWidget {
  const MyAccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final noneOn = ref.watch(selectedInstitutionIdsProvider).value?.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('My accounts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Pesa Clarity reads messages only from the accounts switched on '
            'here, and only on this phone.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 16),
          const InstitutionList(control: InstitutionControl.toggle),
          if (noneOn ?? false) ...[
            const SizedBox(height: 12),
            Text(
              'All accounts are off, so no messages are read.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
