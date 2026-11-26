import 'package:material_ui/material_ui.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import 'value_tile.dart';

/// How a [ChoiceMenu] shows that its filter is narrowing what shows.
enum ChoiceHighlight {
  /// A solid brand-red pill with light text.
  fill,

  /// The plain pill, unchanged, with its label and arrow in the link red,
  /// as the chosen side of a switch is.
  text,
}

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
    this.highlightAs = ChoiceHighlight.fill,
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

  /// Marks the pill, for a filter that is narrowing what shows, in the way
  /// [highlightAs] says.
  final bool highlight;

  /// How [highlight] shows: a red fill, or red text with no fill.
  final ChoiceHighlight highlightAs;

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
    // A choice that narrows the list is filled with the brand red, or, as
    // the chosen side of a switch is, keeps the plain pill with its label
    // in the link red.
    final filled = highlight && highlightAs == ChoiceHighlight.fill;
    final fill = filled ? scheme.primary : colors.field;
    final ink = filled
        ? scheme.onPrimary
        : highlight
        ? colors.link
        : scheme.onSurface;
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
            side: BorderSide(color: filled ? fill : colors.border),
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
                        // A form field's choice wraps at larger text rather
                        // than lose its end, such as "Your M-Pesa (KES 250
                        // is the stall's)".
                        maxLines: expand ? 3 : 1,
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
