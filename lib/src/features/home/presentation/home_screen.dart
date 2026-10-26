import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/widgets/feature_placeholder.dart';
import '../../../shared/widgets/hero_figure_card.dart';

/// Home tab: how am I doing today?
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go(AppRoutes.profile),
          ),
        ],
      ),
      body: const FeaturePlaceholder(
        hero: HeroFigureCard(
          label: 'Safe to spend today',
          figure: 'KES —',
          caption: 'Shows once your messages have been read.',
        ),
        question: 'How am I doing today?',
        contents: [
          'Safe to spend today, with weekday and weekend limits',
          'Plan used and left this month, and runway',
          'Financial Health Index and its change',
          'Upcoming bills',
          'The + button to add a transaction or import a statement',
        ],
      ),
    );
  }
}
