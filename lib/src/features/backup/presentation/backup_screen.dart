import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../application/backup_labels.dart';
import '../application/backup_providers.dart';
import '../application/backup_service.dart';
import '../data/backup_location.dart';
import '../data/backup_settings_repository.dart';
import 'restore_flow.dart';

/// Backup and restore, under Profile.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  BackupController get _controller =>
      ref.read(backupControllerProvider.notifier);

  Future<bool> _ensureSetUp(BackupSettings settings) async {
    if (settings.isSetUp) return true;
    final done = await context.push<bool>(AppRoutes.backupSetup);
    return done ?? false;
  }

  Future<void> _toggle(
    BackupSettings settings,
    BackupLocationId id,
    bool on,
  ) async {
    if (on && !await _ensureSetUp(settings)) return;
    await _controller.setEnabled(id, on);
  }

  Future<void> _backUpNow(BackupSettings settings) async {
    if (!await _ensureSetUp(settings)) return;
    final active = _controller.activeLocations(
      await ref.read(backupControllerProvider.future),
    );
    if (active.isEmpty) {
      _tell('Turn on a place to back up to, or use Share a copy.');
      return;
    }
    await _run('Backing up', () async {
      final report = await _controller.backUpNow();
      if (report.failed.isEmpty) {
        _tell('Backed up.');
      } else {
        final problems = [
          for (final MapEntry(:key, :value) in report.failed.entries)
            '${key.label}: $value',
        ].join('\n');
        _tell(
          report.succeeded.isEmpty ? problems : 'Backed up, except:\n$problems',
        );
      }
    });
  }

  Future<void> _share(BackupSettings settings) async {
    if (!await _ensureSetUp(settings)) return;
    await _run('Preparing a copy', () async {
      final file = await ref.read(backupServiceProvider).createShareCopy();
      await ref
          .read(fileSharerProvider)
          .shareFile(
            file,
            subject: 'Pesa Clarity backup',
            text:
                'Encrypted Pesa Clarity backup. It opens with your '
                'passphrase or recovery key.',
          );
    });
  }

  Future<void> _run(String label, Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on BackupNotSetUpException {
      _tell('Set up backups first.');
    } on BackupLocationException catch (e) {
      _tell(e.message);
    } on Exception {
      _tell('The backup stopped before it finished. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tell(String message) {
    if (mounted) showNote(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(backupControllerProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleBackup,
          child: const Text('Backup and restore'),
        ),
      ),
      body: settings == null ? const LoadingView() : _body(context, settings),
    );
  }

  Widget _body(BuildContext context, BackupSettings settings) {
    final availability = ref.watch(backupAvailabilityProvider);
    final driveAllowed = ref.watch(driveAllowedProvider);
    final now = ref.watch(clockProvider)();
    final enabled = settings.enabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _StatusCard(settings: settings, now: now),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        const SectionLabel('Back up to'),
        GroupedSection(
          children: [
            _DestinationTile(
              key: const Key('backup-vault'),
              title: BackupLocationId.vault.label,
              subtitle: !availability.vault
                  ? 'Available when the vault service opens'
                  : availability.signedIn
                  ? 'Encrypted copies on the Pesa Clarity server'
                  : 'Sign in from Profile to use it',
              value:
                  availability.vaultReady &&
                  enabled.contains(BackupLocationId.vault),
              onChanged: availability.vaultReady && !_busy
                  ? (on) => _toggle(settings, BackupLocationId.vault, on)
                  : null,
            ),
            if (driveAllowed)
              _DestinationTile(
                key: const Key('backup-drive'),
                title: BackupLocationId.drive.label,
                subtitle: availability.drive
                    ? 'Your own account · '
                          '${enabled.contains(BackupLocationId.drive) ? 'connected' : 'not connected'}'
                    : 'Your own account · coming soon',
                value:
                    availability.drive &&
                    enabled.contains(BackupLocationId.drive),
                onChanged: availability.drive && !_busy
                    ? (on) => _toggle(settings, BackupLocationId.drive, on)
                    : null,
              ),
            _DestinationTile(
              key: const Key('backup-device'),
              title: BackupLocationId.deviceFolder.label,
              subtitle: settings.folder == null
                  ? '.pcbackup file in a folder you choose · offline'
                  : '.pcbackup file in ${settings.folder!.name} · offline',
              value: enabled.contains(BackupLocationId.deviceFolder),
              onChanged: _busy
                  ? null
                  : (on) =>
                        _toggle(settings, BackupLocationId.deviceFolder, on),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ButtonPair(
          primary: FilledButton(
            onPressed: _busy ? null : () => _backUpNow(settings),
            child: const Text('Back up now'),
          ),
          secondary: OutlinedButton(
            onPressed: _busy ? null : () => _share(settings),
            child: const Text('Share a copy'),
          ),
        ),
        const SectionLabel('Restore from'),
        GroupedSection(
          footer:
              'Restores need your passphrase or recovery key. Your current '
              'data stays until the restore succeeds.',
          children: [
            _SourceTile(
              title: 'Vault',
              trailing: !availability.vault
                  ? 'Coming soon'
                  : availability.signedIn
                  ? 'See backups'
                  : 'Sign in first',
              onTap: availability.vaultReady && !_busy
                  ? () => _restoreFrom(
                      settings,
                      BackupLocationId.vault,
                      'Vault backups',
                    )
                  : null,
            ),
            if (driveAllowed)
              _SourceTile(
                title: 'Google Drive',
                trailing: availability.drive ? 'Sign in' : 'Coming soon',
                onTap: availability.drive && !_busy
                    ? () => _restoreFrom(
                        settings,
                        BackupLocationId.drive,
                        'Google Drive backups',
                      )
                    : null,
              ),
            if (settings.folder != null)
              _SourceTile(
                title: settings.folder!.name,
                trailing: 'See backups',
                onTap: _busy
                    ? null
                    : () => _restoreFrom(
                        settings,
                        BackupLocationId.deviceFolder,
                        'Backups in ${settings.folder!.name}',
                      ),
              ),
            _SourceTile(
              title: 'A file on this phone',
              trailing: 'Choose file',
              onTap: _busy ? null : () => restoreFromPickedFile(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (settings.folder != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _controller.changeFolder,
              child: const Text('Change backup folder'),
            ),
          ),
        if (settings.isSetUp)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => context.push<bool>(AppRoutes.backupSetup),
              child: const Text('Change passphrase and recovery key'),
            ),
          ),
      ],
    );
  }

  Future<void> _restoreFrom(
    BackupSettings settings,
    BackupLocationId id,
    String title,
  ) async {
    final location = _controller.locationFor(id, settings);
    if (location == null) return;
    if (id == BackupLocationId.drive) {
      final auth = ref.read(driveAuthProvider);
      if (await auth.currentAccount() == null && await auth.signIn() == null) {
        return;
      }
    }
    if (!mounted) return;
    await restoreFromLocation(context, ref, location, title);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.settings, required this.now});

  final BackupSettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final last = settings.lastSuccessAt;
    final (Tone tone, IconData icon, String text) = switch ((
      settings.isSetUp,
      last,
    )) {
      (_, final DateTime at) => (
        Tone.success,
        Icons.check,
        'Backed up ${backupTimeLabel(at, now)}. Encrypted with your '
            'passphrase before upload.',
      ),
      (true, null) => (
        Tone.info,
        Icons.lock_outline,
        'Ready to back up. Every copy is encrypted with your passphrase on '
            'this phone.',
      ),
      (false, null) => (
        Tone.info,
        Icons.lock_outline,
        'Set up encrypted backups. Choose a passphrase and save your '
            'recovery key to start.',
      ),
    };

    return Column(
      key: const Key('backup-status'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Notice(text, tone: tone, icon: icon),
        if (!settings.isSetUp)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.push<bool>(AppRoutes.backupSetup),
              child: const Text('Set up'),
            ),
          ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return ListTile(
      title: Text(title, style: theme.textTheme.bodyMedium),
      // What a tap does, or why the row is off.
      trailing: onTap == null
          ? Text(
              trailing,
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            )
          : TrailingLink(trailing),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
