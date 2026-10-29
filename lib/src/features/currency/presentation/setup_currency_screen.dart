import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../application/currency_controller.dart';
import 'currency_picker.dart';

/// Onboarding: the currency the person counts in, their region's suggested.
class SetupCurrencyScreen extends ConsumerStatefulWidget {
  const SetupCurrencyScreen({super.key});

  @override
  ConsumerState<SetupCurrencyScreen> createState() =>
      _SetupCurrencyScreenState();
}

class _SetupCurrencyScreenState extends ConsumerState<SetupCurrencyScreen> {
  String? _picked;
  var _saving = false;

  Future<void> _continue(String code) async {
    setState(() => _saving = true);
    await ref.read(currencyControllerProvider.notifier).choose(code);
    if (mounted) context.go(AppRoutes.onboardingAccounts);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final region = ref.watch(deviceRegionProvider);
    final settings = ref.watch(currencyControllerProvider).value;
    final suggested = currencyOfRegion(region);
    final picked =
        _picked ??
        (settings?.chosen ?? false
            ? settings!.base
            : suggested ?? settings?.base ?? BaseCurrency.code);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleCurrency,
          child: const Text('Your currency'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CurrencyPicker(
                selected: picked,
                suggested: suggested,
                onSelected: (code) => setState(() => _picked = code),
                header: [
                  Text(
                    'Which currency do you count in?',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Totals, budgets and goals show in this one. Money in '
                    "other currencies is converted at today's rate.",
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: PesaColors.of(context).textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MergeSemantics(
                    child: Semantics(
                      identifier: SemanticIds.onboardingCurrencyContinue,
                      child: FilledButton(
                        onPressed: settings == null || _saving
                            ? null
                            : () => _continue(picked),
                        child: Text('Continue with $picked'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Change anytime in Profile',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
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
