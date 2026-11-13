import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// One choice of more than two, as a drop-down: a pill showing the current
/// choice that opens a menu of all of them. Used in place of a row of chip
/// buttons, which grows with every option.
class ChoiceMenu<T> extends StatelessWidget {
  const ChoiceMenu({
    required this.options,
    required this.value,
    required this.onChanged,
    this.name,
    this.highlight = false,
    this.expand = false,
    this.itemKey,
    super.key,
  });

  /// Each choice and its label, in menu order.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// What is being chosen, such as `Account`, for screen readers.
  final String? name;

  /// Fills the pill, for a filter that is narrowing what shows.
  final bool highlight;

  /// Takes the full width, for a form field.
  final bool expand;

  /// A key for each menu row, for tests and UI flows.
  final Key Function(T option)? itemKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = PesaColors.of(context);
    final current = options
        .where((o) => o.$1 == value)
        .map((o) => o.$2)
        .firstOrNull;
    final text = current ?? '';
    // A choice that narrows the list is picked out with a neutral tint and
    // a text-coloured edge, not red.
    final fill = highlight ? colors.selected : colors.field;
    final ink = scheme.onSurface;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final (option, label) in options)
          MenuItemButton(
            key: itemKey?.call(option),
            leadingIcon: Icon(
              Icons.check,
              size: 18,
              color: option == value ? scheme.onSurface : Colors.transparent,
            ),
            onPressed: () => onChanged(option),
            child: Text(label),
          ),
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        label: '${name == null ? '' : '$name: '}$text. Change',
        excludeSemantics: true,
        child: Material(
          color: fill,
          shape: StadiumBorder(
            side: BorderSide(color: highlight ? ink : colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Layout.minTouch),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Flexible(
                      fit: expand ? FlexFit.tight : FlexFit.loose,
                      child: Text(
                        text,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge!.copyWith(color: ink),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down, size: 22, color: ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
