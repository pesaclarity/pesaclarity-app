import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_placeholder.dart';

/// Statement import, opened from the + button on Home.
class ImportStatementScreen extends StatelessWidget {
  const ImportStatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import a statement')),
      body: const FeaturePlaceholder(
        question: 'Bring in your history',
        contents: [
          'M-Pesa and bank PDF statements, password-protected ones too',
          'Matches each line against messages already read, so nothing '
              'counts twice',
          'Checks the result against the statement\'s closing balance',
        ],
      ),
    );
  }
}
