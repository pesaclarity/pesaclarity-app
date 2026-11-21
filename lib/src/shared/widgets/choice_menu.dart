import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import 'value_tile.dart';

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
    this.fill,
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

  /// Marks a filter that is narrowing what shows: its label turns red.
  final bool highlight;

  /// A fill for the pill at rest, for Activity's filters, which keep the
  /// look they had: filled, and filled with brand red while narrowing,
  /// with the chosen menu row in the text colour. Without it the pill is
  /// plain, with a grey edge, and says what is chosen in red.
  final Color? fill;

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
    final filled = fill != null;
    // A choice that narrows the list says so in red: as a red label on the
    // plain pill, or, where the pill is [fill]ed, as a brand-red pill.
    final background = !filled
        ? Colors.transparent
        : highlight
        ? scheme.primary
        : fill!;
    final ink = !highlight
        ? scheme.onSurface
        : filled
        ? scheme.onPrimary
        : colors.link;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final (option, label) in options)
          MenuItemButton(
            key: itemKey?.call(option),
            leadingIcon: Icon(
              Icons.check,
              size: 18,
              color: option == value ? colors.link : Colors.transparent,
            ),
            onPressed: () => onChanged(option),
            child: Text(
              label,
              style: option == value && !filled
                  ? TextStyle(color: colors.link)
                  : null,
            ),
          ),
      ],
      builder: (context, menu, _) => Semantics(
        button: true,
        label: '${name == null ? '' : '$name: '}$text. Change',
        excludeSemantics: true,
        child: Material(
          color: background,
          shape: StadiumBorder(
            side: BorderSide(
              color: filled && highlight ? background : colors.border,
            ),
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

/// A row with a [ChoiceMenu] at its end, such as "Lock after": a
/// [ValueTile], so the menu moves under the title at larger text, where
/// the title would otherwise be left less than a word's width beside it.
class ChoiceTile<T> extends ValueTile {
  const ChoiceTile({
    required super.title,
    required ChoiceMenu<T> super.trailing,
    super.subtitle,
    super.leading,
    super.enabled,
    super.contentPadding,
    super.key,
  });
}
