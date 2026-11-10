import 'package:flutter/material.dart';

import '../../../theme/pesa_colors.dart';

/// The heading of a step that explains something, such as "Let Pesa
/// Clarity read your account messages". Used by the SMS scan and the
/// statement import.
class ExplainHeading extends StatelessWidget {
  const ExplainHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);
}

/// A muted paragraph under an [ExplainHeading].
class ExplainBody extends StatelessWidget {
  const ExplainBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: PesaColors.of(context).textMuted),
  );
}

/// Short promises, each after a tick, such as what reading SMS means.
class TickPoints extends StatelessWidget {
  const TickPoints(this.points, {super.key});

  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(child: Text(point, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}
