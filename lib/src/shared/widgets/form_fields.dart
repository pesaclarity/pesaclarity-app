import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../core/time/clock.dart';
import '../../domain/time/calendar.dart';
import '../adaptive/adaptive.dart';
import '../format/date_labels.dart';

/// A text field for an amount, read with [parseMoneyMinor]. Every typed
/// amount uses it.
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.label,
    this.allowZero = false,
    this.maxMinor,
    this.currency,
    this.hint,
    this.onChanged,
    this.validator,
    this.autofocus = false,
    super.key,
  });

  /// Opens the keyboard on this field when the form shows.
  final bool autofocus;

  final TextEditingController controller;
  final String label;

  /// A further check once the amount itself is fine, such as "Enter a
  /// price for each line." Gets the amount in minor units.
  final String? Function(int amountMinor)? validator;

  /// Shown before the amount; the base currency by default.
  final String? currency;
  final String? hint;
  final ValueChanged<String>? onChanged;

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
        hintText: hint,
        prefixText: '${currency ?? BaseCurrency.code} ',
      ),
      onChanged: onChanged,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final value = amountFrom(text ?? '', currency: currency);
        if (value == null) return 'Enter an amount, such as 5,000.';
        if (!allowZero && value == 0) return 'Enter an amount above 0.';
        final max = maxMinor;
        if (max != null && value > max) {
          return 'Up to ${formatMoney(Money(max, currency: currency))}.';
        }
        return validator?.call(value);
      },
    );
  }

  /// The amount in [text] in minor units of [currency] (the base currency
  /// by default): 0 for an empty field or 0, null when it is not an amount.
  static int? amountFrom(String text, {String? currency}) {
    final clean = text.trim();
    if (clean.isEmpty || RegExp(r'^0+(\.0*)?$').hasMatch(clean)) return 0;
    return parseMoneyMinor(clean, currency: currency);
  }
}

/// A tappable row that picks a day with the date picker. It reads the
/// way people say the day: `Today`, `Yesterday`, `Mon 3 Nov`, with the
/// year only when it isn't this year.
class DateField extends ConsumerWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.emptyText = 'Choose a date',
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
  Widget build(BuildContext context, WidgetRef ref) {
    final date = value;
    final today = CalendarDate.local(ref.watch(clockProvider)());
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
        child: Text(date == null ? emptyText : _say(date, today)),
      ),
    );
  }
}

/// `Today`, `Yesterday`, `Mon 3 Nov`, or `Mon 3 Nov 2025` in another year.
String _say(CalendarDate date, CalendarDate today) {
  final day = dayHeading(date, today: today);
  return date.year == today.year ? day : '$day ${date.year}';
}
