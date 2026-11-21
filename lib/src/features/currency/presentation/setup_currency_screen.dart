import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../onboarding/presentation/setup_parts.dart';
import '../application/currency_controller.dart';
import 'currency_picker.dart';

/// Onboarding: the currency the person counts in, their region's suggested.
///
/// It never waits on the saved settings: on a new phone there are none, so
/// the suggested currency shows and Continue works from the first frame.
/// Saved settings (someone coming back to this step) take over once read.
class SetupCurrencyScreen extends ConsumerStatefulWidget {
  const SetupCurrencyScreen({super.key});

  @override
  ConsumerState<SetupCurrencyScreen> createState() =>
      _SetupCurrencyScreenState();
}

class _SetupCurrencyScreenState extends ConsumerState<SetupCurrencyScreen> {
  String? _picked;

  var _saving = false;
  var _failed = false;

  Future<void> _continue(String code) async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await ref.read(currencyControllerProvider.notifier).choose(code);
    } on Object catch (error) {
      debugPrint('The currency could not be saved: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return;
    }
    if (mounted) context.go(AppRoutes.onboardingIncome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final region = ref.watch(deviceRegionProvider);
    // Only what is already read; a read that fails or never ends changes
    // nothing here.
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
                      color: colors.textMuted,
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
                  SetupAction(
                    identifier: SemanticIds.onboardingCurrencyContinue,
                    label: 'Continue with $picked',
                    busy: _saving,
                    problem: _failed
                        ? 'Your currency could not be saved.'
                        : null,
                    onPressed: () => _continue(picked),
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
