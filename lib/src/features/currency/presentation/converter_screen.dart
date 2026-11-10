import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency_data.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../application/currency_controller.dart';
import '../data/rates_client.dart';
import 'base_currency_screen.dart';
import 'currency_picker.dart';

/// How much of [to] one [from] buys with [settings]' rates, own rates
/// first. Null when either has no rate.
double? crossRate(CurrencySettings settings, String from, String to) {
  final converter = settings.converter;
  final a = converter.rateFor(from);
  final b = converter.rateFor(to);
  return a == null || b == null ? null : b / a;
}

/// Profile › Base currency › Currency converter: any amount between any two
/// currencies, at the latest rates or the person's own.
class ConverterScreen extends ConsumerStatefulWidget {
  const ConverterScreen({super.key});

  @override
  ConsumerState<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends ConsumerState<ConverterScreen> {
  final _amount = TextEditingController(text: '100');
  String? _from;
  String? _to;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<String?> _pick(String selected) => Navigator.of(context).push(
    MaterialPageRoute<String>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Choose a currency')),
        body: CurrencyPicker(
          selected: selected,
          onSelected: (code) => Navigator.of(context).pop(code),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final settings = ref.watch(currencyControllerProvider).value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final base = settings.base;
    // The person's other currencies: their accounts', then their own rates'.
    final theirs = <String>{
      for (final a in accounts.values) a.currency,
      ...settings.ownRates.keys,
    }..remove(base);
    final from = _from ?? base;
    final to = _to ?? (theirs.isNotEmpty ? theirs.first : _fallback(base));
    final amount = parseMoneyMinor(_amount.text, currency: from);
    final rate = crossRate(settings, from, to);
    String inCurrency(String code) {
      final r = crossRate(settings, from, code);
      if (amount == null || r == null) return '–';
      final minor =
          amount *
          r *
          _pow10(minorUnitDigits(code)) /
          _pow10(minorUnitDigits(from));
      return formatMoney(
        Money(minor.round(), currency: code),
        withCurrency: false,
        alwaysShowMinorUnits: true,
      );
    }

    final others = [
      for (final code in {base, ...theirs})
        if (code != from && code != to) code,
    ];
    final source = ref.watch(ratesSourceProvider);
    final configured = ref.watch(ratesConfiguredProvider);
    final fetched = settings.rates?.fetchedAt;
    final today = CalendarDate.local(ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: const Text('Currency converter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _CodeButton(
                        key: const Key('converter-from'),
                        code: from,
                        onPressed: () async {
                          final code = await _pick(from);
                          if (code != null) setState(() => _from = code);
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('converter-amount'),
                          controller: _amount,
                          textAlign: TextAlign.end,
                          style: AppTypography.amount(
                            size: 26,
                            color: theme.colorScheme.onSurface,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Amount in $from',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: IconButton(
                      key: const Key('converter-swap'),
                      tooltip: 'Swap currencies',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () => setState(() {
                        _from = to;
                        _to = from;
                      }),
                    ),
                  ),
                  Row(
                    children: [
                      _CodeButton(
                        key: const Key('converter-to'),
                        code: to,
                        onPressed: () async {
                          final code = await _pick(to);
                          if (code != null) setState(() => _to = code);
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          inCurrency(to),
                          key: const Key('converter-result'),
                          textAlign: TextAlign.end,
                          style: AppTypography.amount(
                            size: 26,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    rate == null
                        ? 'No rate between $from and $to yet. Set your own '
                              'rate, or refresh once you are online.'
                        : '1 $from = ${formatRate(rate)} $to · '
                              '1 $to = ${formatRate(1 / rate)} $from',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (others.isNotEmpty && amount != null) ...[
            const SizedBox(height: 16),
            Text(
              '${formatMoney(Money(amount, currency: from))} in your other '
              'currencies',
              style: theme.textTheme.labelLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final code in others)
                    ListTile(
                      leading: Text(
                        code,
                        style: theme.textTheme.labelLarge!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      title: Text(currencyCatalogue[code]?.name ?? code),
                      subtitle: Text(
                        crossRate(settings, from, code) == null
                            ? 'No rate yet'
                            : '1 $from = '
                                  '${formatRate(crossRate(settings, from, code)!)} $code'
                                  '${settings.ownRates.containsKey(code) ? ' · your rate' : ''}',
                      ),
                      trailing: Text(
                        inCurrency(code),
                        style: AppTypography.amount(
                          size: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => showOwnRateDialog(context, settings),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Set my own rate'),
              ),
              if (configured)
                TextButton.icon(
                  onPressed: () => ref
                      .read(currencyControllerProvider.notifier)
                      .refreshRates(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh rates'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !configured
                ? 'Only the rates you set.'
                : fetched == null
                ? 'Rates load once you are online.'
                : '${source == null ? 'Rates' : 'Rates by ${source.name}'}, '
                      'updated ${_when(CalendarDate.local(fetched), fetched, today)}. '
                      'With no connection, the converter uses the last rates.',
            key: const Key('converter-credit'),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  static String _fallback(String base) => base == 'USD' ? 'EUR' : 'USD';

  static String _when(CalendarDate day, DateTime at, CalendarDate today) =>
      day == today ? 'today at ${formatTime(at)}' : shortDate(day);

  static double _pow10(int n) {
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({required this.code, required this.onPressed, super.key});

  final String code;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: currencyCatalogue[code]?.name ?? code,
          excludeSemantics: true,
          child: Text(code),
        ),
        const Icon(Icons.arrow_drop_down),
      ],
    ),
  );
}
