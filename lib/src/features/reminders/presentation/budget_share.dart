import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/reminders/reminder_settings.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';

/// The menu choice that opens the custom share sheet.
const customShareChoice = -2;

/// The menu choices for a budget alert share: the fixed shares, then
/// [current] when it is a custom one, then "Custom…". [defaultLabel]
/// marks the default share in Profile.
List<(int, String)> shareChoices(int current, {bool markDefault = true}) => [
  for (final percent in ReminderSettings.budgetAlertPercentChoices)
    (
      percent,
      markDefault && percent == ReminderSettings.defaultBudgetAlertPercent
          ? '$percent% (default)'
          : '$percent%',
    ),
  if (current > 0 &&
      !ReminderSettings.budgetAlertPercentChoices.contains(current))
    (current, '$current%'),
  (customShareChoice, 'Custom…'),
];

/// A "Warn me at" menu. Picking "Custom…" asks for a number first.
/// [shownAs] says how the pill shows the choice when not as in the menu,
/// such as `80%` for `80% (default)`.
ChoiceMenu<int> shareMenu(
  BuildContext context, {
  required List<(int, String)> options,
  required int value,
  required ValueChanged<int> onChanged,
  String Function(int value)? shownAs,
  Key? key,
}) => ChoiceMenu<int>(
  key: key,
  name: 'Warn me at',
  options: [
    for (final (option, label) in options)
      (option, option == value && shownAs != null ? shownAs(option) : label),
  ],
  value: value,
  itemKey: (option) => Key('warn-at-$option'),
  onChanged: (option) async {
    if (option != customShareChoice) {
      onChanged(option);
      return;
    }
    final typed = await showCustomShareSheet(
      context,
      initial: value > 0 ? value : null,
    );
    if (typed != null) onChanged(typed);
  },
);

/// Asks for a share from 10 to 150 percent. Null when closed.
Future<int?> showCustomShareSheet(BuildContext context, {int? initial}) =>
    showAppSheet<int>(
      context: context,
      builder: (context) => _CustomShare(initial: initial),
    );

class _CustomShare extends StatefulWidget {
  const _CustomShare({this.initial});

  final int? initial;

  @override
  State<_CustomShare> createState() => _CustomShareState();
}

class _CustomShareState extends State<_CustomShare> {
  late final _field = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_field.text.trim());
    const min = ReminderSettings.minBudgetAlertPercent;
    const max = ReminderSettings.maxBudgetAlertPercent;
    if (value == null || value < min || value > max) {
      setState(() => _error = 'Type a whole number from $min to $max.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => SheetBody(
    title: 'Warn me at',
    subtitle: 'The share of a category’s plan used before an alert comes.',
    children: [
      TextField(
        key: const Key('custom-share'),
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Share of the plan',
          suffixText: '%',
          errorText: _error,
          helperText:
              'Any whole number from 10 to 150. At 100 you hear only when '
              'the plan is used up.',
          helperMaxLines: 3,
        ),
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
