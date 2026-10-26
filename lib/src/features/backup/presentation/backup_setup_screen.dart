import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/backup/backup.dart';
import '../../../core/time/clock.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../application/backup_providers.dart';
import '../data/backup_location.dart';
import '../data/backup_settings_repository.dart';
import '../data/backup_sharing.dart';

/// Minimum passphrase length for new backups.
const minPassphraseLength = 8;

/// Where the setup screen writes the recovery key PDF before saving it.
final recoveryKeyScratchDirectoryProvider = Provider<Future<Directory>>(
  (ref) async =>
      Directory(p.join((await getTemporaryDirectory()).path, 'recovery-key'))
          .create(recursive: true),
);

/// Two steps: choose a passphrase, then save the recovery key shown once.
class BackupSetupScreen extends ConsumerStatefulWidget {
  const BackupSetupScreen({super.key});

  @override
  ConsumerState<BackupSetupScreen> createState() => _BackupSetupScreenState();
}

class _BackupSetupScreenState extends ConsumerState<BackupSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  RecoveryKey? _recoveryKey;
  bool _obscure = true;
  bool _kept = false;
  bool _saving = false;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _recoveryKey = RecoveryKey.generate());
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    await ref
        .read(backupControllerProvider.notifier)
        .completeSetup(
          BackupSecrets(
            passphrase: _passphrase.text,
            recoveryKey: _recoveryKey!,
          ),
        );
    if (!mounted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final key = _recoveryKey;
    return Scaffold(
      appBar: AppBar(
        title: Text(key == null ? 'Set up backups' : 'Your recovery key'),
      ),
      body: SafeArea(
        child: key == null ? _passphraseStep(context) : _keyStep(context, key),
      ),
    );
  }

  Widget _passphraseStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Every backup is locked with this passphrase on your phone before '
            'it goes anywhere. Pick one you will remember; you need it to '
            'restore.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _passphrase,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              helperText:
                  'At least $minPassphraseLength characters. '
                  'A short sentence works well.',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show passphrase' : 'Hide passphrase',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) => (value ?? '').length < minPassphraseLength
                ? 'Use at least $minPassphraseLength characters.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Type it again'),
            validator: (value) => value != _passphrase.text
                ? 'The two passphrases differ.'
                : null,
            onFieldSubmitted: (_) => _continue(),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _continue, child: const Text('Continue')),
        ],
      ),
    );
  }

  Widget _keyStep(BuildContext context, RecoveryKey key) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final groups = key.toDisplayString().split('-');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'This key opens your backups if you forget your passphrase. It is '
          'shown only now, so save or print it before you finish.',
          style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              [
                for (var i = 0; i < groups.length; i += 2)
                  groups.skip(i).take(2).join('  '),
              ].join('\n'),
              key: const Key('recovery-key-text'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier', BrandTokens.bodyFont],
                letterSpacing: 1.5,
                height: 1.7,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _savePdf(key),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Save as PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => _print(key),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
            ),
            OutlinedButton.icon(
              onPressed: () => _shareText(key),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share as text'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _kept,
          onChanged: (value) => setState(() => _kept = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I have saved my recovery key somewhere safe'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _kept && !_saving ? _finish : null,
          child: const Text('Finish'),
        ),
      ],
    );
  }

  Future<void> _savePdf(RecoveryKey key) => _guard(() async {
    final now = ref.read(clockProvider)();
    final bytes = await recoveryKeyPdf(key, now);
    final dir = await ref.read(recoveryKeyScratchDirectoryProvider);
    final file = File(p.join(dir.path, 'recovery-key.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      final saved = await ref
          .read(documentStorageProvider)
          .saveAs(
            file,
            'Pesa Clarity recovery key.pdf',
            mimeType: 'application/pdf',
          );
      if (saved) _tell('Recovery key saved.');
    } finally {
      await file.delete();
    }
  });

  Future<void> _print(RecoveryKey key) => _guard(() async {
    final bytes = await recoveryKeyPdf(key, ref.read(clockProvider)());
    await ref
        .read(documentPrinterProvider)
        .printPdf(bytes, name: 'Pesa Clarity recovery key');
  });

  Future<void> _shareText(RecoveryKey key) => _guard(
    () => ref
        .read(fileSharerProvider)
        .shareText(
          recoveryKeyText(key, ref.read(clockProvider)()),
          subject: 'Pesa Clarity recovery key',
        ),
  );

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on BackupLocationException catch (e) {
      _tell(e.message);
    } on Exception {
      _tell('That did not work. Try another option.');
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
