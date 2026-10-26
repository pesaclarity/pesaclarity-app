import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';

/// Body for screens that are not built yet: the question the screen answers
/// and what it will show, taken from the product spec.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    required this.question,
    required this.contents,
    this.hero,
    this.actions = const [],
    super.key,
  });

  /// The one question this screen answers, for example "How am I doing today?".
  final String question;

  /// What the finished screen will show.
  final List<String> contents;

  /// Optional card shown above the question, such as the main number.
  final Widget? hero;

  /// Buttons or links to screens one level deeper.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (hero != null) ...[hero!, const SizedBox(height: 16)],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                for (final item in contents)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: colors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(item, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Not built yet. This screen is a placeholder.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        for (final action in actions) ...[const SizedBox(height: 12), action],
      ],
    );
  }
}
