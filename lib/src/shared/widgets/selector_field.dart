import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';
import 'app_sheet.dart';

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
    // The one field style: the label above, the value on an underline, no
    // box and no fill.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Text(label, style: theme.textTheme.bodyMedium)),
        Semantics(
          button: true,
          label: '$label: $value. Change',
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                enabled: onTap != null,
                suffixIcon: Icon(Icons.chevron_right, color: colors.textMuted),
              ),
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
          ),
        ),
      ],
    );
  }
}

/// A short list to pick one from, shown in full in a bottom sheet: radio
/// rows on Android, a grouped list with a tick on iPhone. Returns the picked
/// value, or null when dismissed.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T? selected,
}) => showAppSheet<T>(
  context: context,
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

/// Picks one of a few settings values from a dialog of radio rows.
Future<T?> pickOne<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<T>(
          groupValue: selected,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            children: [
              for (final (value, label) in options)
                RadioListTile<T>(value: value, title: Text(label)),
            ],
          ),
        ),
      ],
    ),
  );
}
