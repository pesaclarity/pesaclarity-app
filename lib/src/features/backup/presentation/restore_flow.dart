import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/backup/backup.dart';
import '../../../core/time/clock.dart';
import '../../../theme/pesa_colors.dart';
import '../application/backup_labels.dart';
import '../application/backup_providers.dart';
import '../data/backup_location.dart';
import '../data/local_database_backup.dart';

/// Where a picked file is copied before it is opened.
final restoreScratchFileProvider = Provider<Future<File>>((ref) async {
  final dir = await Directory(
    p.join((await getTemporaryDirectory()).path, 'backup', 'picked'),
  ).create(recursive: true);
  return File(p.join(dir.path, 'picked.pcbackup'));
});

/// Restores from [location]: pick a backup by date, fetch it, then unlock.
Future<void> restoreFromLocation(
  BuildContext context,
  WidgetRef ref,
  BackupLocation location,
  String title,
) async {
  final entry = await showModalBottomSheet<BackupEntry>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _BackupListSheet(location: location, title: title),
  );
  if (entry == null || !context.mounted) return;
  final file = await _withProgress(
    context,
    'Fetching the backup',
    () => ref.read(backupServiceProvider).fetch(location, entry),
  );
  if (file == null || !context.mounted) return;
  await _unlockAndRestore(context, ref, file);
}

/// Restores from a file the user picks with the system picker.
Future<void> restoreFromPickedFile(BuildContext context, WidgetRef ref) async {
  final storage = ref.read(documentStorageProvider);
  final picked = await storage.pickFile();
  if (picked == null || !context.mounted) return;
  final file = await _withProgress(context, 'Reading the file', () async {
    final target = await ref.read(restoreScratchFileProvider);
    await storage.copyToFile(picked.uri, target);
    return target;
  });
  if (file == null || !context.mounted) return;
  await _unlockAndRestore(context, ref, file);
}

Future<void> _unlockAndRestore(
  BuildContext context,
  WidgetRef ref,
  File file,
) async {
  final manifest = await showDialog<BackupManifest>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RestoreDialog(file: file),
  );
  await ref.read(backupServiceProvider).clearTemporaryFiles();
  if (file.existsSync()) await file.delete();
  if (manifest == null || !context.mounted) return;
  final when = backupTimeLabel(manifest.createdAt, ref.read(clockProvider)());
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('Restored. Your data is from $when.')),
    );
}

Future<T?> _withProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProgressDialog(label: label),
    ),
  );
  try {
    final value = await work();
    navigator.pop();
    return value;
  } on Exception catch (e) {
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(restoreErrorMessage(e))));
    return null;
  }
}

/// Plain words for anything that stops a restore.
String restoreErrorMessage(Object error) => switch (error) {
  WrongBackupCredentialException() =>
    'That passphrase or recovery key does not open this backup.',
  InvalidRecoveryKeyException(:final message) => message,
  NotABackupFileException() => 'This file is not a Pesa Clarity backup.',
  BackupIntegrityException() =>
    'This backup is damaged or incomplete. Your data is unchanged.',
  BackupException(:final message) => '$message Your data is unchanged.',
  RestoredDataException(:final message) => '$message Your data is unchanged.',
  BackupLocationException(:final message) => message,
  _ => 'The restore stopped. Your data is unchanged.',
};

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

class _BackupListSheet extends StatefulWidget {
  const _BackupListSheet({required this.location, required this.title});

  final BackupLocation location;
  final String title;

  @override
  State<_BackupListSheet> createState() => _BackupListSheetState();
}

class _BackupListSheetState extends State<_BackupListSheet> {
  late final Future<List<BackupEntry>> _entries = widget.location.list();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final now = DateTime.now();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(widget.title, style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: FutureBuilder<List<BackupEntry>>(
                future: _entries,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(restoreErrorMessage(snapshot.error!)),
                    );
                  }
                  final entries = snapshot.data;
                  if (entries == null) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Backups you make here will show up here.'),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        title: Text(backupTimeLabel(entry.createdAt, now)),
                        subtitle: entry.sizeBytes == null
                            ? null
                            : Text(
                                _size(entry.sizeBytes!),
                                style: theme.textTheme.bodySmall!.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(entry),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Asks for the passphrase or recovery key and runs the restore.
///
/// Pops with the restored backup's manifest, or null if cancelled.
class RestoreDialog extends ConsumerStatefulWidget {
  const RestoreDialog({required this.file, super.key});

  final File file;

  @override
  ConsumerState<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<RestoreDialog> {
  final _secret = TextEditingController();
  bool _useRecoveryKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final text = _secret.text.trim();
    if (text.isEmpty) return;
    final BackupCredential credential;
    try {
      credential = _useRecoveryKey
          ? RecoveryKeyCredential(RecoveryKey.parse(text))
          : PassphraseCredential(_secret.text);
    } on InvalidRecoveryKeyException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final manifest = await ref
          .read(backupServiceProvider)
          .restoreFromFile(widget.file, credential);
      ref.invalidate(backupControllerProvider);
      if (mounted) Navigator.of(context).pop(manifest);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = restoreErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Restore this backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The backup replaces the data on this phone once it opens and '
                'checks out. Until then, your current data stays.',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('restore-secret'),
                controller: _secret,
                enabled: !_busy,
                obscureText: !_useRecoveryKey,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: _useRecoveryKey
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: _useRecoveryKey ? 'Recovery key' : 'Passphrase',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _restore(),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _useRecoveryKey = !_useRecoveryKey;
                        _secret.clear();
                        _error = null;
                      }),
                child: Text(
                  _useRecoveryKey
                      ? 'Use my passphrase'
                      : 'Use my recovery key instead',
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  'Opening and checking the backup',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}
