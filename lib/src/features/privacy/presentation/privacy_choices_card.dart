import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/privacy/consent.dart';
import '../../app_status/application/update_check_choice.dart';
import '../../app_status/application/update_links.dart';
import '../../counting/application/counting.dart';
import '../../crash_reports/application/crash_reports.dart';
import '../../crash_reports/presentation/crash_choice_sheet.dart';
import '../application/consent_controller.dart';
import 'privacy_widgets.dart';

/// Labels of the ADR 0024 rows in Privacy.
abstract final class PrivacyRowLabels {
  static const updateCheck = (
    'Check for updates daily',
    'Asks our server for new versions and notices. Off until you say yes',
  );
  static const counting = (
    'Count this phone in monthly totals',
    'A random number, new each month, sent with the update check. '
        'Never your data',
  );
  static const crashReports = 'Crash reports';
}

/// Privacy's choices once policy 2.4 is agreed (ADR 0024): the two consent
/// switches, the F-Droid build's daily update check, counting, and crash
/// reports, which open their own sheet.
class PrivacyChoicesCard extends ConsumerWidget {
  const PrivacyChoicesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(consentControllerProvider).value;
    final fdroid = ref.watch(updateChannelProvider) == UpdateChannel.foss;
    final updateCheck = ref.watch(updateCheckChoiceProvider);
    final counting = ref.watch(countingControllerProvider);
    final crash = ref.watch(crashReportChoiceProvider).value;

    Widget consent(ConsentKind kind) => CheckboxListTile(
      title: Text(consentLabels[kind]!.$1),
      subtitle: Text(consentLabels[kind]!.$2),
      value: record?.valueOf(kind) ?? kind.defaultValue,
      onChanged: record == null
          ? null
          : (value) => ref
                .read(consentControllerProvider.notifier)
                .setChoice(kind, value ?? false),
      controlAffinity: ListTileControlAffinity.trailing,
    );

    return Card(
      child: Column(
        children: [
          consent(ConsentKind.improveApp),
          const Divider(height: 1),
          consent(ConsentKind.licensedModels),
          if (fdroid) ...[
            const Divider(height: 1),
            CheckboxListTile(
              title: Text(PrivacyRowLabels.updateCheck.$1),
              subtitle: Text(PrivacyRowLabels.updateCheck.$2),
              value: updateCheck.value ?? false,
              onChanged: updateCheck.isLoading
                  ? null
                  : (value) => ref
                        .read(updateCheckChoiceProvider.notifier)
                        .answer(value ?? false),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ],
          const Divider(height: 1),
          CheckboxListTile(
            title: Text(PrivacyRowLabels.counting.$1),
            subtitle: Text(PrivacyRowLabels.counting.$2),
            value: counting.value ?? false,
            onChanged: counting.isLoading
                ? null
                : (value) => ref
                      .read(countingControllerProvider.notifier)
                      .setEnabled(value ?? false),
            controlAffinity: ListTileControlAffinity.trailing,
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text(PrivacyRowLabels.crashReports),
            subtitle: Text(crash == null ? '' : crashChoiceLabels[crash]!.$1),
            trailing: const Icon(Icons.chevron_right),
            enabled: crash != null,
            onTap: () => showCrashChoiceSheet(context),
          ),
        ],
      ),
    );
  }
}
