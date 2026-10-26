import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../routing/app_routes.dart';
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
      _tell('Tick a place to back up to, or use Share a copy.');
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(backupControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, settings),
    );
  }

  Widget _body(BuildContext context, BackupSettings settings) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
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
        const _SectionLabel('BACK UP TO'),
        _Group(
          children: [
            _DestinationTile(
              key: const Key('backup-vault'),
              title: BackupLocationId.vault.label,
              subtitle: availability.vault
                  ? 'Encrypted copies on the Pesa Clarity server'
                  : 'Available when the vault service opens',
              value:
                  availability.vault &&
                  enabled.contains(BackupLocationId.vault),
              onChanged: availability.vault && !_busy
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
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _backUpNow(settings),
                child: const Text('Back up now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _share(settings),
                child: const Text('Share a copy'),
              ),
            ),
          ],
        ),
        const _SectionLabel('RESTORE FROM'),
        _Group(
          children: [
            _SourceTile(
              title: 'Vault',
              trailing: availability.vault ? 'See backups' : 'Coming soon',
              onTap: availability.vault && !_busy
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
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text(
            'Restores need your passphrase or recovery key. Your current data '
            'stays until the restore succeeds.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
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
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final scheme = theme.colorScheme;
    final last = settings.lastSuccessAt;

    final (
      Color background,
      Color foreground,
      IconData icon,
      String title,
      String body,
    ) = switch ((settings.isSetUp, last)) {
      (_, final DateTime at) => (
        colors.success.withValues(alpha: 0.1),
        colors.successText,
        Icons.check,
        'Backed up ${backupTimeLabel(at, now)}',
        'Encrypted with your passphrase before upload',
      ),
      (true, null) => (
        colors.brandSoft,
        scheme.onSurface,
        Icons.lock_outline,
        'Ready to back up',
        'Every copy is encrypted with your passphrase on this phone',
      ),
      (false, null) => (
        colors.brandSoft,
        scheme.onSurface,
        Icons.lock_outline,
        'Set up encrypted backups',
        'Choose a passphrase and save your recovery key to start',
      ),
    };

    return Container(
      key: const Key('backup-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(icon, color: last == null ? scheme.primary : colors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: foreground,
                  ),
                ),
                Text(
                  body,
                  style: theme.textTheme.bodySmall!.copyWith(color: foreground),
                ),
              ],
            ),
          ),
          if (!settings.isSetUp)
            TextButton(
              onPressed: () => context.push<bool>(AppRoutes.backupSetup),
              child: const Text('Set up'),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
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
    return CheckboxListTile(
      value: value,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      controlAffinity: ListTileControlAffinity.trailing,
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
      trailing: Text(
        '$trailing ›',
        style: theme.textTheme.bodyMedium!.copyWith(
          color: colors.textMuted,
          fontSize: 13,
        ),
      ),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
