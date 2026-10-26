import 'package:flutter/material.dart';

import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';

/// Insights tab: what should I change?
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleInsights,
          child: const Text('Insights'),
        ),
      ),
      body: const FeaturePlaceholder(
        question: 'What should I change?',
        contents: [
          'Leakage total and its share of income',
          'Where it goes: lifestyle, friends, family, fees',
          'Six-month trend',
          'A one-page PDF report',
        ],
      ),
    );
  }
}
