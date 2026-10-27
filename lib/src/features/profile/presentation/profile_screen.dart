import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/flavor.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/presentation/account_section.dart';
import '../../backup/application/backup_labels.dart';
import '../../backup/application/backup_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../export/application/export_service.dart';
import '../../export/presentation/export_sheet.dart';
import '../../reminders/presentation/reminders_settings_card.dart';
import '../../security/presentation/device_warning_card.dart';
import '../../security/presentation/security_settings_card.dart';
import '../../statements/data/pdf_text_extractor.dart';
import '../../subscriptions/application/subscriptions_providers.dart';

/// Profile, one level under Home: accounts, settings, backup and privacy.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flavor = ref.watch(appFlavorProvider);
    final canImport = ref.watch(statementImportAvailableProvider);
    final subscriptions = ref.watch(subscriptionsOverviewProvider).value;
    final backupSettings = ref.watch(backupControllerProvider).value;
    final lastBackup = backupSettings == null
        ? null
        : lastBackupSummary(backupSettings, ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleProfile,
          child: const Text('Profile'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const AccountCard(),
          const SizedBox(height: 16),
          const DeviceWarningCard(),
          Card(
            child: Column(
              children: [
                Semantics(
                  identifier: SemanticIds.profileMyAccounts,
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('My accounts'),
                    subtitle: const Text('Choose whose messages are read'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(AppRoutes.myAccounts),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Payees'),
                  subtitle: const Text('Names, categories and leak types'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.payees),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('profile-base-currency'),
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('Base currency'),
                  subtitle: Text(ref.watch(baseCurrencyProvider)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.baseCurrency),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('profile-subscriptions'),
                  leading: const Icon(Icons.autorenew),
                  title: const Text('Subscriptions'),
                  subtitle: Text(
                    subscriptions == null || subscriptions.lines.isEmpty
                        ? 'What repeats, and what it costs'
                        : '${formatMoney(Money(subscriptions.monthlyTotalMinor), withCurrency: false)} a month',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.subscriptions),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export data'),
                  subtitle: const Text('CSV · Excel · PDF'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      showExportSheet(context, const FullWorkbookExport()),
                ),
                const Divider(height: 1),
                if (canImport) ...[
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Import a statement'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.importStatement),
                  ),
                  const Divider(height: 1),
                ],
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
          const SizedBox(height: 4),
          const SecuritySettingsCard(),
          const SizedBox(height: 16),
          const RemindersSettingsCard(),
          const SizedBox(height: 16),
          const AccountActions(),
        ],
      ),
    );
  }
}
