import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_placeholder.dart';

/// Backup and restore, under Profile.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: const FeaturePlaceholder(
        question: 'Is my data safe if I lose this phone?',
        contents: [
          'When the last backup succeeded',
          'Destinations you switch on separately: Pesa Clarity vault, your '
              'own Google Drive, phone or SD card',
          'Back up now, and Share a copy',
          'Restore from any source with your passphrase or recovery key',
          'Every backup is encrypted on this phone before it goes anywhere',
        ],
      ),
    );
  }
}
