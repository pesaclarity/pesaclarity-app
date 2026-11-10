import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// A small capitals label over a group of rows, such as `TODAY` over the
/// day's entries or `HISTORY` over an item's moves.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(0, 20, 0, 8),
    super.key,
  });

  /// Written as people say it; it shows in capitals.
  final String text;

  /// A small action or total at the right, such as `In 1,500 · Out 0`.
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: PesaColors.of(context).textMuted, letterSpacing: 1);
    final label = Semantics(
      header: true,
      child: Text(text.toUpperCase(), semanticsLabel: text, style: style),
    );
    return Padding(
      padding: padding,
      child: trailing == null
          ? label
          : Row(
              children: [
                Expanded(child: label),
                trailing!,
              ],
            ),
    );
  }
}

/// A section's title in sentence case, with an optional [action] at the
/// right, such as "Add a goal".
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    this.action,
    this.padding = const EdgeInsets.fromLTRB(0, 24, 0, 8),
    super.key,
  });

  final String text;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    return Padding(
      padding: padding,
      child: action == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                action!,
              ],
            ),
    );
  }
}

/// A tab's title row: the title at the left, then the tab's [actions], with
/// the eye last. Every tab but Home starts with it.
class TabHeader extends StatelessWidget {
  const TabHeader(
    this.title, {
    this.semanticsId,
    this.actions = const [],
    super.key,
  });

  final String title;

  /// For UI flows, from `SemanticIds`.
  final String? semanticsId;

  /// Links to the tab's other screens as text buttons, then the eye.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Layout.titleGap),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            identifier: semanticsId,
            header: true,
            // A long title shrinks to one line rather than wrapping
            // under the actions.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                title,
                maxLines: 1,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
          ),
        ),
        ...actions,
      ],
    ),
  );
}
