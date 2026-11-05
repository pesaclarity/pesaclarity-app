import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/build_info.dart';
import '../../../config/flavor.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/look/look_settings.dart';
import '../../../domain/spaces/space.dart';
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
import '../../income/application/income_providers.dart';
import '../../look/application/look_providers.dart';
import '../../reminders/presentation/reminders_settings_card.dart';
import '../../security/presentation/device_warning_card.dart';
import '../../security/presentation/security_settings_card.dart';
import '../../spaces/application/spaces_providers.dart';
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
    // Only iPhone needs the Shortcuts automation to capture messages.
    final ios = defaultTargetPlatform == TargetPlatform.iOS;

    final myAccounts = Semantics(
      identifier: SemanticIds.profileMyAccounts,
      child: ListTile(
        leading: const RowIcon(Icons.account_balance_outlined),
        title: const Text('My accounts'),
        subtitle: const Text('Choose whose messages are read'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.myAccounts),
      ),
    );
    final connect = ListTile(
      key: const Key('profile-connect-messages'),
      leading: const RowIcon(Icons.sms_outlined),
      title: const Text('Connect messages'),
      subtitle: const Text('The Shortcuts automation'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.connectMessages),
    );
    final payees = ListTile(
      leading: const RowIcon(Icons.people_outline),
      title: const Text('Payees'),
      subtitle: const Text('Names, categories and leak types'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.payees),
    );
    final sources = ref.watch(incomeSourcesProvider).value;
    final income = ListTile(
      key: const Key('profile-income'),
      leading: const RowIcon(Icons.payments_outlined),
      title: const Text('How money comes in'),
      subtitle: Text(
        sources == null || !sources.answered
            ? 'Salary, business, support and more'
            : [
                for (final s in IncomeSource.values)
                  if (sources.picked.contains(s)) s.label,
              ].join(', '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.incomeSources),
    );
    final currency = ListTile(
      key: const Key('profile-base-currency'),
      leading: const RowIcon(Icons.currency_exchange),
      title: const Text('Base currency'),
      subtitle: Text(ref.watch(baseCurrencyProvider)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.baseCurrency),
    );
    final timezone = ListTile(
      key: const Key('profile-timezone'),
      leading: const RowIcon(Icons.schedule),
      title: const Text('Timezone'),
      subtitle: Text(ref.watch(userTimeZoneProvider).displayName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showTimeZoneSheet(context, ref),
    );
    final lookNow = ref.watch(currentLookProvider);
    final look = ListTile(
      key: const Key('profile-look'),
      leading: const RowIcon(Icons.palette_outlined),
      title: const Text('Look'),
      subtitle: Text(
        '${lookNow.theme.label} theme · '
        '${lookNow.fields.label.toLowerCase()} fields',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLookSheet(context, ref),
    );
    final subscriptionsRow = ListTile(
      key: const Key('profile-subscriptions'),
      leading: const RowIcon(Icons.autorenew),
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
      leading: const RowIcon(Icons.file_download_outlined),
      title: const Text('Export data'),
      subtitle: const Text('CSV · Excel · PDF'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showExportSheet(context, const FullWorkbookExport()),
    );
    final importRow = ListTile(
      leading: const RowIcon(Icons.description_outlined),
      title: const Text('Import a statement'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.importStatement),
    );
    final backup = Semantics(
      identifier: SemanticIds.profileBackup,
      child: ListTile(
        leading: const RowIcon(Icons.cloud_upload_outlined),
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
    );
    final privacy = Semantics(
      identifier: SemanticIds.profilePrivacy,
      child: ListTile(
        leading: const RowIcon(Icons.lock_outline),
        title: const Text('Privacy'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.privacy),
      ),
    );
    final buildRow = ListTile(
      leading: const RowIcon(Icons.info_outline),
      title: const Text('Build'),
      subtitle: Text(buildLabel(ref.watch(buildVersionProvider), flavor)),
    );
    final businessRouting = ListTile(
      key: const Key('profile-business-or-personal'),
      leading: const RowIcon(Icons.call_split_outlined),
      title: const Text('Business or personal'),
      subtitle: const Text("Where each account's money goes"),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.businessOrPersonal),
    );
    final documents = ListTile(
      key: const Key('profile-documents'),
      leading: const RowIcon(Icons.receipt_long_outlined),
      title: const Text('Receipts and invoices'),
      subtitle: const Text('Business details, numbering, how to pay'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.documentSettings),
    );
    final money = [
      myAccounts,
      if (ref.watch(activeSpaceProvider).kind == SpaceKind.business) ...[
        businessRouting,
        documents,
      ],
      if (ios) connect,
      income,
      payees,
      currency,
      timezone,
      look,
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

  void _showLookSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final look = ref.watch(currentLookProvider);
          final theme = Theme.of(context);
          Widget heading(String title, String note) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(
                  note,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: PesaColors.of(context).textMuted,
                  ),
                ),
              ],
            ),
          );
          Future<void> save(LookSettings next) =>
              ref.read(lookSettingsProvider.notifier).save(next);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.75,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  heading('Theme', 'System follows your phone.'),
                  for (final t in ThemeChoice.values)
                    ListTile(
                      key: Key('look-theme-${t.name}'),
                      title: Text(t.label),
                      trailing: t == look.theme
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => save(look.copyWith(theme: t)),
                    ),
                  heading('Text fields', 'How boxes you type in look.'),
                  for (final f in FieldStyle.values)
                    ListTile(
                      key: Key('look-fields-${f.name}'),
                      title: Text(f.label),
                      trailing: f == look.fields
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => save(look.copyWith(fields: f)),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
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
