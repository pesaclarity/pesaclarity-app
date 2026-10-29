import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';

/// Lists up to this long show in full, with no search; longer ones show the
/// most used and a search box.
const shortListLimit = 7;

/// A form field that shows its value and opens a picker when tapped, in
/// place of a drop-down menu.
class SelectorField extends StatelessWidget {
  const SelectorField({
    required this.label,
    required this.value,
    required this.onTap,
    this.detail,
    super.key,
  });

  final String label;
  final String value;

  /// A second line under the value, such as what the choice means.
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ),
        Semantics(
          button: true,
          label: '$label: $value. Change',
          excludeSemantics: true,
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(value, style: theme.textTheme.bodyLarge),
                            if (detail != null)
                              Text(
                                detail!,
                                style: theme.textTheme.bodySmall!.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A short list to pick one from, shown in full in a bottom sheet. Returns
/// the picked value, or null when dismissed.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T? selected,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: RadioGroup<T>(
                groupValue: selected,
                onChanged: (value) => Navigator.of(context).pop(value),
                child: Column(
                  children: [
                    for (final (i, (value, label)) in options.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      RadioListTile<T>(
                        value: value,
                        title: Text(
                          label,
                          style: value == selected
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
