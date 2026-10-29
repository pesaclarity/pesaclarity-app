import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../domain/time/calendar.dart';
import '../../domain/time/date_labels.dart';
import '../adaptive/adaptive.dart';

/// A text field for an amount in the base currency, read with [parseMoneyMinor].
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.label,
    this.allowZero = false,
    this.maxMinor,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  /// Accepts an empty field or 0 as nothing.
  final bool allowZero;

  /// The most it accepts, such as what is left on a loan.
  final int? maxMinor;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${BaseCurrency.code} ',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final value = amountFrom(text ?? '');
        if (value == null) return 'Enter an amount, such as 5,000.';
        if (!allowZero && value == 0) return 'Enter an amount above 0.';
        final max = maxMinor;
        if (max != null && value > max) {
          return 'Up to ${formatMoney(Money(max))}.';
        }
        return null;
      },
    );
  }

  /// The amount in [text] in minor units: 0 for an empty field or 0, null
  /// when it is not an amount.
  static int? amountFrom(String text) {
    final clean = text.trim();
    if (clean.isEmpty || RegExp(r'^0+(\.0*)?$').hasMatch(clean)) return 0;
    return parseMoneyMinor(clean);
  }
}

/// A tappable row that picks a day with the date picker.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.emptyText = 'Pick a date',
    this.clearable = false,
    super.key,
  });

  final String label;
  final CalendarDate? value;
  final ValueChanged<CalendarDate?> onChanged;
  final CalendarDate firstDate;
  final CalendarDate lastDate;
  final String emptyText;

  /// Shows a button that sets the date back to none.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        DateTime asDay(CalendarDate d) => DateTime(d.year, d.month, d.day);
        final initial = date ?? firstDate;
        final picked = await pickDate(
          context,
          initialDate: asDay(
            initial.isAfter(lastDate)
                ? lastDate
                : (initial.isBefore(firstDate) ? firstDate : initial),
          ),
          firstDate: asDay(firstDate),
          lastDate: asDay(lastDate),
        );
        if (picked != null) {
          onChanged(CalendarDate(picked.year, picked.month, picked.day));
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && date != null
              ? IconButton(
                  tooltip: 'Clear date',
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(date == null ? emptyText : dateLabel(date)),
      ),
    );
  }
}
