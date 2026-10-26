import 'package:flutter/material.dart';

import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';

/// Activity tab: where did my money go?
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleActivity,
          child: const Text('Activity'),
        ),
      ),
      body: const FeaturePlaceholder(
        question: 'Where did my money go?',
        contents: [
          'Search, account and type filters, and export',
          'Weekly money in and out',
          'Transactions grouped by day',
          'Own transfers shown as not spending',
          'Unknown numbers prompt you to name the payee',
        ],
      ),
    );
  }
}
