import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_placeholder.dart';

/// Plan tab: what's coming, and is it covered?
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan')),
      body: const FeaturePlaceholder(
        question: "What's coming, and is it covered?",
        contents: [
          'Month switcher',
          'Planned against expected income, split by debt, tax, living '
              'and school',
          'Category status: Done, In progress, Over',
          'How the surplus is split between debt and savings',
        ],
      ),
    );
  }
}
