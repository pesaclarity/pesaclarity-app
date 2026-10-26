import 'package:flutter/material.dart';

import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';

/// Debts, one level under Goals: when will I be debt-free?
class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleDebts,
          child: const Text('Debts'),
        ),
      ),
      body: const FeaturePlaceholder(
        question: 'When will I be debt-free?',
        contents: [
          'Remaining balance across every debt, family loans included',
          'Payoff strategy: avalanche, snowball or custom',
          "This payday's split",
          'Fuliza tracker: draws, fees and days overdrawn',
          'What-if slider',
        ],
      ),
    );
  }
}
