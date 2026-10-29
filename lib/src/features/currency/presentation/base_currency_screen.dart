import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currency_data.dart';
import '../../../core/money/exchange_rates.dart';
import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../application/currency_controller.dart';
import '../data/rates_client.dart';
import 'currency_picker.dart';

/// `129.2`, `0.00774`: enough digits to read a rate either way round.
String formatRate(double rate) {
  final digits = rate >= 100
      ? 2
      : rate >= 1
      ? 3
      : 5;
  final text = rate.toStringAsFixed(digits);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// Profile › Base currency: the currency totals are counted in, today's
/// rates, and rates the person sets.
class BaseCurrencyScreen extends ConsumerWidget {
  const BaseCurrencyScreen({super.key});

  Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    CurrencySettings settings,
    String code,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final rate = settings.converter.rateFor(code);
    if (rate == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Add a rate for $code first: refresh the rates, or set your own.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('Count in $code?'),
        content: Text(
          'Your plan, goals, debts, loans and subscriptions move to $code at '
          '1 ${settings.base} = ${formatRate(rate)} $code. Each transaction '
          'keeps the currency it was paid in.',
        ),
        actions: [
          DialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep ${settings.base}'),
          ),
          DialogAction(
            destructive: true,
            filled: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text('Switch to $code'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(currencyControllerProvider.notifier).switchTo(code);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currencyControllerProvider).value;
    final region = ref.watch(deviceRegionProvider);
    final configured = ref.watch(ratesConfiguredProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(title: const Text('Base currency')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : CurrencyPicker(
              selected: settings.base,
              suggested: currencyOfRegion(region),
              onSelected: (code) => _switch(context, ref, settings, code),
              subtitleOf: (code) {
                if (code == settings.base) return null;
                final rate = settings.converter.rateFor(code);
                if (rate == null) return null;
                final own = settings.ownRates.containsKey(code);
                return '1 ${settings.base} = ${formatRate(rate)} $code'
                    '${own ? ' · your rate' : ''}';
              },
              header: [
                _RatesCard(
                  settings: settings,
                  configured: configured,
                  today: today,
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

class _RatesCard extends ConsumerStatefulWidget {
  const _RatesCard({
    required this.settings,
    required this.configured,
    required this.today,
  });

  final CurrencySettings settings;
  final bool configured;
  final CalendarDate today;

  @override
  ConsumerState<_RatesCard> createState() => _RatesCardState();
}

class _RatesCardState extends ConsumerState<_RatesCard> {
  var _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final fresh = await ref
        .read(currencyControllerProvider.notifier)
        .refreshRates(force: true);
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (!fresh) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rates update once you are online. Try again soon.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final settings = widget.settings;
    final source = ref.watch(ratesSourceProvider);
    final rates = settings.rates;
    final fetched = rates == null ? null : CalendarDate.local(rates.fetchedAt);
    final status = !widget.configured
        ? 'Only the rates you set'
        : fetched == null
        ? 'Rates load once you are online'
        : fetched == widget.today
        ? 'Rates updated today'
        : 'Rates from ${shortDate(fetched)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Totals show in ${settings.base}. Each transaction keeps the '
              'currency it was paid in.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              status,
              key: const Key('rates-status'),
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (widget.configured && source != null)
              Align(
                alignment: Alignment.centerLeft,
                child: source.link == null
                    ? Text(
                        'Rates by ${source.name}',
                        key: const Key('rates-credit'),
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.textMuted,
                        ),
                      )
                    : Semantics(
                        link: true,
                        child: InkWell(
                          key: const Key('rates-credit'),
                          onTap: () =>
                              ref.read(linkOpenerProvider)(source.link!),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Rates by ${source.name}',
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.link,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.link,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (widget.configured)
                  TextButton.icon(
                    onPressed: _refreshing ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh rates'),
                  ),
                TextButton.icon(
                  key: const Key('own-rate'),
                  onPressed: () => showOwnRateDialog(context, settings),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Set my own rate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a currency and how much of it one base unit buys.
Future<void> showOwnRateDialog(
  BuildContext context,
  CurrencySettings settings,
) => showDialog<void>(
  context: context,
  builder: (context) => _OwnRateDialog(settings),
);

class _OwnRateDialog extends ConsumerStatefulWidget {
  const _OwnRateDialog(this.settings);

  final CurrencySettings settings;

  @override
  ConsumerState<_OwnRateDialog> createState() => _OwnRateDialogState();
}

class _OwnRateDialogState extends ConsumerState<_OwnRateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _rate = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _rate.dispose();
    super.dispose();
  }

  String get _cleanCode => _code.text.trim().toUpperCase();

  Future<void> _save({bool clear = false}) async {
    if (!_formKey.currentState!.validate() && !clear) return;
    final controller = ref.read(currencyControllerProvider.notifier);
    await controller.setOwnRate(
      _cleanCode,
      clear ? null : double.parse(_rate.text.trim().replaceAll(',', '')),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.settings.base;
    final code = _cleanCode;
    final hasOwn = widget.settings.ownRates.containsKey(code);
    return AlertDialog(
      title: const Text('Set my own rate'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('own-rate-code'),
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Currency code',
                hintText: 'USD',
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final c = (v ?? '').trim().toUpperCase();
                if (!currencyCatalogue.containsKey(c)) {
                  return 'Enter a code such as USD';
                }
                return c == base ? 'Pick a currency other than $base' : null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('own-rate-value'),
              controller: _rate,
              decoration: InputDecoration(
                labelText:
                    '1 $base buys how much ${code.isEmpty ? 'of it' : code}?',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final rate = double.tryParse(
                  (v ?? '').trim().replaceAll(',', ''),
                );
                return rate == null || rate <= 0
                    ? 'Enter a rate, such as 0.0077'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (hasOwn)
          TextButton(
            onPressed: () => _save(clear: true),
            child: const Text('Use the fetched rate'),
          ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
