import 'package:flutter/material.dart';

import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';

/// Privacy, under Profile: promises, consent switches and the full policy.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titlePrivacy,
          child: const Text('Privacy'),
        ),
      ),
      body: const FeaturePlaceholder(
        question: 'What leaves my phone?',
        contents: [
          'Plain-language promises',
          'Improve the app (federated updates): on by default',
          'Contribute to licensed models: off by default',
          'Crash reports: off by default',
          'The full policy, its version and date, and Email me a copy',
        ],
      ),
    );
  }
}
