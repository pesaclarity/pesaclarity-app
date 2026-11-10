import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/currency_controller.dart';
import '../data/rates_client.dart';
import 'base_currency_screen.dart';

/// `1 USD = 129.2 KES`, written the way round that reads as more than one.
String ratePair(String base, String code, double baseBuys) => baseBuys >= 1
    ? '1 $base = ${formatRate(baseBuys)} $code'
    : '1 $code = ${formatRate(1 / baseBuys)} $base';

/// [record] in the base currency, or null when it is in the base already
/// or there is no rate for it.
Converted? baseValueOf(WidgetRef ref, TransactionRecord record) {
  final converter = ref.watch(currencyConverterProvider);
  return record.currency == converter.base
      ? null
      : convertRecord(record, converter);
}

/// The base amount and rate of a payment in another currency, with a way to
/// set the rate the person got. Nothing for a payment in the base currency.
class PaymentRateCard extends ConsumerWidget {
  const PaymentRateCard(this.record, {super.key});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(baseCurrencyProvider);
    if (record.currency == base) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final converted = baseValueOf(ref, record);
    final source = ref.watch(ratesSourceProvider)?.name;
    final from = source == null ? '' : ', from $source';
    final day = converted?.day;
    final note = switch (converted?.kind) {
      null =>
        "There is no rate for ${record.currency} yet, so this isn't in "
            'your $base totals. It counts once rates load, or set the rate '
            'you got.',
      RateKind.got => 'The rate you got for this payment.',
      RateKind.own => 'Your own rate for ${record.currency}.',
      RateKind.sameDay || RateKind.earlierDay =>
        'The rate of ${shortDate(day!)}$from. It stays with this payment, '
            "so later rates don't change it.",
      RateKind.approximate =>
        'Approximate: the oldest rate the app has, from ${shortDate(day!)}. '
            'Rates are kept from the day the app first loads them.',
      RateKind.latest =>
        'The latest rate$from, until rates are kept day by day.',
    };

    return Card(
      key: const Key('payment-rate'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Exchange rate',
              style: theme.textTheme.labelLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (converted != null) ...[
              const SizedBox(height: 4),
              Text(
                ratePair(base, record.currency, converted.baseBuys),
                style: theme.textTheme.titleMedium,
              ),
            ],
            const SizedBox(height: 4),
            Text(note, style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('rate-got'),
                    onPressed: () => showRateGotDialog(
                      context,
                      record: record,
                      base: base,
                      current: converted?.baseBuys,
                    ),
                    child: Text(
                      converted?.kind == RateKind.got
                          ? 'Change the rate I got'
                          : 'Use the rate I got',
                    ),
                  ),
                  if (converted?.kind == RateKind.got)
                    TextButton(
                      key: const Key('rate-day'),
                      onPressed: () => ref
                          .read(transactionsRepositoryProvider)
                          .setRateGot(record.id, currency: base),
                      child: const Text("Use the day's rate"),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `≈ USD 193.50` under a payment's amount, when it is in another currency.
class BaseAmountLine extends ConsumerWidget {
  const BaseAmountLine(this.record, {super.key});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final converted = baseValueOf(ref, record);
    if (converted == null) return const SizedBox.shrink();
    final base = ref.watch(baseCurrencyProvider);
    return Text(
      '≈ ${shownMoney(context, converted.baseMinor, currency: base)}',
      key: const Key('payment-base-amount'),
      style: Theme.of(context).textTheme.titleMedium!
          .copyWith(color: PesaColors.of(context).textMuted),
    );
  }
}

/// Asks what one [base] unit bought of the payment's currency, the way
/// round that reads as more than one, and saves it on [record].
Future<void> showRateGotDialog(
  BuildContext context, {
  required TransactionRecord record,
  required String base,
  double? current,
}) => showAdaptiveDialog<void>(
  context: context,
  builder: (context) =>
      _RateGotDialog(record: record, base: base, current: current),
);

class _RateGotDialog extends ConsumerStatefulWidget {
  const _RateGotDialog({
    required this.record,
    required this.base,
    required this.current,
  });

  final TransactionRecord record;
  final String base;
  final double? current;

  @override
  ConsumerState<_RateGotDialog> createState() => _RateGotDialogState();
}

class _RateGotDialogState extends ConsumerState<_RateGotDialog> {
  final _formKey = GlobalKey<FormState>();
  late final bool _baseFirst = (widget.current ?? 1) >= 1;
  late final _rate = TextEditingController(
    text: widget.current == null
        ? ''
        : formatRate(_baseFirst ? widget.current! : 1 / widget.current!),
  );

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  static double? _parse(String? text) {
    final value = double.tryParse((text ?? '').replaceAll(',', '').trim());
    return value == null || value <= 0 ? null : value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final value = _parse(_rate.text)!;
    final navigator = Navigator.of(context);
    await ref
        .read(transactionsRepositoryProvider)
        .setRateGot(
          widget.record.id,
          currency: widget.base,
          rate: _baseFirst ? value : 1 / value,
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.record.currency;
    final (one, other) = _baseFirst ? (widget.base, code) : (code, widget.base);
    return AlertDialog(
      title: const Text('The rate I got'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('rate-got-field'),
          controller: _rate,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '1 $one bought how much $other?',
            suffixText: other,
          ),
          validator: (v) =>
              _parse(v) == null ? 'Enter a rate, such as 129.5.' : null,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        DialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        DialogAction(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
