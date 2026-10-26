import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/flavor.dart';
import '../../../core/time/clock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/feature_placeholder.dart';
import '../../../theme/pesa_colors.dart';
import '../../backup/application/backup_labels.dart';
import '../../backup/application/backup_providers.dart';

/// Profile, one level under Home: accounts, settings, backup and privacy.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flavor = ref.watch(appFlavorProvider);
    final backupSettings = ref.watch(backupControllerProvider).value;
    final lastBackup = backupSettings == null
        ? null
        : lastBackupSummary(backupSettings, ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FeaturePlaceholder(
        question: 'Your account and settings',
        contents: const [
          'Account details',
          'My accounts: the institutions whose messages the app reads',
          'Payday and currency',
          'Import, export and backup',
          'Security: app lock, hide balances',
          'Sign out and delete account',
        ],
        actions: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('My accounts'),
                  subtitle: const Text('Choose whose messages are read'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.myAccounts),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Backup and restore'),
                  subtitle: Text(
                    lastBackup ?? 'Set up an encrypted backup',
                    key: const Key('profile-last-backup'),
                    style: lastBackup == null
                        ? null
                        : TextStyle(color: PesaColors.of(context).successText),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.backup),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Privacy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.privacy),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Build'),
                  subtitle: Text(flavor.name),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
