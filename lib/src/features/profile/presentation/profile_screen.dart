import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/flavor.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
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
import '../../timezone/application/timezone_controller.dart';

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
    final ios = isCupertino(context);

    final myAccounts = Semantics(
      identifier: SemanticIds.profileMyAccounts,
      child: ListTile(
        leading: const RowIcon(
          Icons.account_balance_outlined,
          cupertinoIcon: CupertinoIcons.building_2_fill,
          color: CupertinoColors.systemRed,
        ),
        title: const Text('My accounts'),
        subtitle: const Text('Choose whose messages are read'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.myAccounts),
      ),
    );
    final connect = ListTile(
      key: const Key('profile-connect-messages'),
      leading: const RowIcon(
        Icons.sms_outlined,
        cupertinoIcon: CupertinoIcons.chat_bubble_fill,
        color: CupertinoColors.systemGreen,
      ),
      title: const Text('Connect messages'),
      subtitle: const Text('The Shortcuts automation'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.connectMessages),
    );
    final payees = ListTile(
      leading: const RowIcon(
        Icons.people_outline,
        cupertinoIcon: CupertinoIcons.person_2_fill,
        color: CupertinoColors.systemPurple,
      ),
      title: const Text('Payees'),
      subtitle: const Text('Names, categories and leak types'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.payees),
    );
    final currency = ListTile(
      key: const Key('profile-base-currency'),
      leading: const RowIcon(
        Icons.currency_exchange,
        cupertinoIcon: CupertinoIcons.money_dollar_circle_fill,
        color: CupertinoColors.systemTeal,
      ),
      title: const Text('Base currency'),
      subtitle: Text(ref.watch(baseCurrencyProvider)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.baseCurrency),
    );
    final timezone = ListTile(
      key: const Key('profile-timezone'),
      leading: const RowIcon(
        Icons.schedule,
        cupertinoIcon: CupertinoIcons.clock_fill,
        color: CupertinoColors.systemOrange,
      ),
      title: const Text('Timezone'),
      subtitle: Text(ref.watch(userTimeZoneProvider).displayName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showTimeZoneSheet(context, ref),
    );
    final subscriptionsRow = ListTile(
      key: const Key('profile-subscriptions'),
      leading: const RowIcon(
        Icons.autorenew,
        cupertinoIcon: CupertinoIcons.arrow_2_squarepath,
        color: CupertinoColors.systemPink,
      ),
      title: const Text('Subscriptions'),
      subtitle: Text(
        subscriptions == null || subscriptions.lines.isEmpty
            ? 'What repeats, and what it costs'
            : '${formatMoney(Money(subscriptions.monthlyTotalMinor), withCurrency: false)} a month',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.subscriptions),
    );
    final export = ListTile(
      leading: const RowIcon(
        Icons.file_download_outlined,
        cupertinoIcon: CupertinoIcons.square_arrow_up,
        color: CupertinoColors.systemGrey,
      ),
      title: const Text('Export data'),
      subtitle: const Text('CSV · Excel · PDF'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showExportSheet(context, const FullWorkbookExport()),
    );
    final importRow = ListTile(
      leading: const RowIcon(
        Icons.description_outlined,
        cupertinoIcon: CupertinoIcons.doc_text_fill,
        color: CupertinoColors.systemBlue,
      ),
      title: const Text('Import a statement'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.importStatement),
    );
    final backup = ListTile(
      leading: const RowIcon(
        Icons.cloud_upload_outlined,
        cupertinoIcon: CupertinoIcons.cloud_upload_fill,
        color: CupertinoColors.systemIndigo,
      ),
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
    );
    final privacy = ListTile(
      leading: const RowIcon(
        Icons.lock_outline,
        cupertinoIcon: CupertinoIcons.lock_fill,
        color: CupertinoColors.systemGrey,
      ),
      title: const Text('Privacy'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.privacy),
    );
    final buildRow = ListTile(
      leading: const RowIcon(
        Icons.info_outline,
        cupertinoIcon: CupertinoIcons.info_circle_fill,
        color: CupertinoColors.systemGrey,
      ),
      title: const Text('Build'),
      subtitle: Text(flavor.name),
    );
    final money = [
      myAccounts,
      if (ios) connect,
      payees,
      currency,
      timezone,
      subscriptionsRow,
    ];
    final data = [export, if (canImport) importRow, backup];
    final about = [privacy, buildRow];

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
          if (ios) ...[
            GroupedSection(header: 'Money', children: money),
            GroupedSection(header: 'Your data', children: data),
            GroupedSection(header: 'About', children: about),
          ] else
            GroupedSection(children: [...money, ...data, ...about]),
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

  void _showTimeZoneSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final current = ref.watch(userTimeZoneProvider);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Select Timezone',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('Device location (Automatic)'),
                  subtitle: Text(
                    '${DateTime.now().timeZoneName} (${UserTimeZone.formatOffset(DateTime.now().timeZoneOffset)})',
                  ),
                  trailing: current.isAuto
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref
                        .read(timeZoneControllerProvider.notifier)
                        .useDeviceLocation();
                  },
                ),
                const Divider(),
                for (final tz in commonTimeZones)
                  ListTile(
                    title: Text(tz.name),
                    subtitle: Text(
                      '${tz.label} · ${UserTimeZone.formatOffset(tz.offset)}',
                    ),
                    trailing:
                        (!current.isAuto &&
                            current.offsetMinutes == tz.offsetMinutes)
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () async {
                      Navigator.pop(context);
                      await ref
                          .read(timeZoneControllerProvider.notifier)
                          .setTimeZone(tz.offset, name: tz.name);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
