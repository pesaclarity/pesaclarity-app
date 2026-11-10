import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/build_info.dart';
import '../../../config/flavor.dart';
import '../../../core/time/clock.dart';
import '../../../domain/income/income_sources.dart';
import '../../../domain/look/look_settings.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/business_day.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/pesa_colors.dart';
import '../../auth/presentation/account_section.dart';
import '../../backup/application/backup_labels.dart';
import '../../backup/application/backup_providers.dart';
import '../../close/application/business_day_providers.dart';
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
      leading: const RowIcon(Icons.currency_exchange_outlined),
      title: const Text('Base currency'),
      subtitle: Text(ref.watch(baseCurrencyProvider)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.baseCurrency),
    );
    final timezone = ListTile(
      key: const Key('profile-timezone'),
      leading: const RowIcon(Icons.schedule_outlined),
      title: const Text('Time zone'),
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
      leading: const RowIcon(Icons.autorenew_outlined),
      title: const Text('Subscriptions'),
      subtitle: Text(
        subscriptions == null || subscriptions.lines.isEmpty
            ? 'What repeats, and what it costs'
            : '${shownMoney(context, subscriptions.monthlyTotalMinor, withCurrency: false)} a month',
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
      leading: const RowIcon(Icons.upload_file_outlined),
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
    final businessDay =
        ref.watch(businessDayProvider).value ?? BusinessDay.midnight;
    final dayEnds = ListTile(
      key: const Key('profile-day-ends'),
      leading: const RowIcon(Icons.nights_stay_outlined),
      title: const Text('Day ends at'),
      subtitle: const Text('For sales today and Close the day'),
      trailing: ChoiceMenu<int>(
        name: 'Day ends at',
        options: [
          for (final hour in BusinessDay.choices)
            (hour, BusinessDay.labelFor(hour)),
        ],
        value: businessDay.endsAtHour,
        itemKey: (hour) => Key('day-ends-$hour'),
        onChanged: (hour) => ref
            .read(businessDayProvider.notifier)
            .save(BusinessDay(endsAtHour: hour)),
      ),
    );
    final money = [
      myAccounts,
      if (ref.watch(activeSpaceProvider).kind == SpaceKind.business) ...[
        businessRouting,
        documents,
        dayEnds,
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
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const AccountCard(),
          const SizedBox(height: 16),
          const DeviceWarningCard(),
          GroupedSection(children: [...money, ...data, ...about]),
          const SecuritySettingsCard(),
          const SizedBox(height: 12),
          const RemindersSettingsCard(),
          const SizedBox(height: 16),
          const AccountActions(),
        ],
      ),
    );
  }

  void _showLookSheet(BuildContext context, WidgetRef ref) {
    showAppSheet<void>(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final look = ref.watch(currentLookProvider);
          final theme = Theme.of(context);
          final muted = PesaColors.of(context).textMuted;
          Future<void> save(LookSettings next) =>
              ref.read(lookSettingsProvider.notifier).save(next);
          return SheetBody(
            title: 'Look',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Theme'),
                subtitle: const Text('System follows your phone.'),
                trailing: ChoiceMenu<ThemeChoice>(
                  key: const Key('look-theme'),
                  name: 'Theme',
                  options: [for (final t in ThemeChoice.values) (t, t.label)],
                  value: look.theme,
                  itemKey: (t) => Key('look-theme-${t.name}'),
                  onChanged: (t) => save(look.copyWith(theme: t)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Text fields',
                style: theme.textTheme.bodyMedium!.copyWith(color: muted),
              ),
              const SizedBox(height: 8),
              AdaptiveSegmented<FieldStyle>(
                key: const Key('look-fields'),
                name: 'Text fields',
                segments: [for (final f in FieldStyle.values) (f, f.label)],
                segmentKey: (f) => Key('look-fields-${f.name}'),
                selected: look.fields,
                onChanged: (f) => save(look.copyWith(fields: f)),
              ),
              const SizedBox(height: 8),
              Text(
                'How boxes you type in look.',
                style: theme.textTheme.bodySmall!.copyWith(color: muted),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTimeZoneSheet(BuildContext context, WidgetRef ref) {
    final current = ref.read(userTimeZoneProvider);
    final controller = ref.read(timeZoneControllerProvider.notifier);
    final now = DateTime.now();
    bool chosen(TimeZoneOption tz) =>
        !current.isAuto &&
        current.offsetMinutes == tz.offsetMinutes &&
        (current.name == null || current.name == tz.name);
    showAppSheet<void>(
      context: context,
      builder: (context) => SheetBody(
        title: 'Choose a time zone',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location_outlined),
            title: const Text('Device location (automatic)'),
            subtitle: Text(
              '${now.timeZoneName} (${UserTimeZone.formatOffset(now.timeZoneOffset)})',
            ),
            trailing: current.isAuto ? const Icon(Icons.check) : null,
            onTap: () async {
              Navigator.pop(context);
              await controller.useDeviceLocation();
            },
          ),
          const Divider(height: 1),
          for (final tz in commonTimeZones)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tz.name),
              subtitle: Text(
                '${tz.label} · ${UserTimeZone.formatOffset(tz.offset)}',
              ),
              trailing: chosen(tz) ? const Icon(Icons.check) : null,
              onTap: () async {
                Navigator.pop(context);
                await controller.setTimeZone(tz.offset, name: tz.name);
              },
            ),
        ],
      ),
    );
  }
}
