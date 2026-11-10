import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../currency/presentation/base_currency_screen.dart' show formatRate;
import '../../currency/presentation/currency_picker.dart';

/// My accounts › the currency of an account added by hand: the one new
/// amounts typed into it are in.
class AccountCurrencyScreen extends ConsumerWidget {
  const AccountCurrencyScreen({required this.accountId, super.key});

  final int accountId;

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    Account account,
    String code,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (code == account.currency) {
      navigator.pop();
      return;
    }
    final repository = ref.read(accountsRepositoryProvider);
    final count = await repository.countInOwnCurrency(account.id);
    if (!context.mounted) return;
    if (count > 0) {
      final base =
          ref.read(currencyControllerProvider).value?.base ?? BaseCurrency.code;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _ChangeCurrencySheet(
              account: account,
              to: code,
              base: base,
              count: count,
            ),
          ),
        ),
      );
      if (confirmed != true) return;
    }
    if (!await repository.setCurrency(account.id, code)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Add a rate for $code first: refresh the rates, or set your own.',
          ),
        ),
      );
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activityAccountsProvider).value?[accountId];
    final settings = ref.watch(currencyControllerProvider).value;
    final region = ref.watch(deviceRegionProvider);
    return Scaffold(
      appBar: AppBar(title: Text('${account?.name ?? 'Account'} currency')),
      body: account == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : CurrencyPicker(
              selected: account.currency,
              suggested: currencyOfRegion(region),
              onSelected: (code) => _choose(context, ref, account, code),
              subtitleOf: (code) {
                if (settings == null || code == settings.base) return null;
                final rate = settings.converter.rateFor(code);
                if (rate == null) return null;
                return '1 ${settings.base} = ${formatRate(rate)} $code';
              },
            ),
    );
  }
}

/// Count a hand-added account in another currency? What was added before
/// keeps its currency.
class _ChangeCurrencySheet extends StatelessWidget {
  const _ChangeCurrencySheet({
    required this.account,
    required this.to,
    required this.base,
    required this.count,
  });

  final Account account;
  final String to;
  final String base;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final from = account.currency;
    final before = count == 1
        ? 'The 1 you added before stays in $from.'
        : 'The $count you added before stay in $from.';
    return Column(
      key: const Key('account-currency-change'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Count ${account.name} in $to?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 14),
        Text(
          'New amounts you add to ${account.name} will be in $to. $before',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 14),
        Text(
          'Totals keep adding each amount in your base currency, $base, at '
          'the rate of its day.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('account-currency-use'),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Use $to'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('account-currency-keep'),
          onPressed: () => Navigator.pop(context, false),
          child: Text('Keep $from'),
        ),
      ],
    );
  }
}
