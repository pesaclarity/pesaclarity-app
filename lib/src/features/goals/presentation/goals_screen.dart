import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';

/// Goals tab: am I getting there?
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleGoals,
          child: const Text('Goals'),
        ),
      ),
      body: FeaturePlaceholder(
        question: 'Am I getting there?',
        contents: const [
          'Debt-free date and progress',
          'Debts at a glance',
          'Goal rings',
          'Net worth and its monthly change',
        ],
        actions: [
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.debts),
            child: const Text('See debts'),
          ),
        ],
      ),
    );
  }
}
