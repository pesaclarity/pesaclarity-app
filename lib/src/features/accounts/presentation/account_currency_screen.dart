import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/exchange_rates.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../currency/presentation/base_currency_screen.dart' show formatRate;
import '../../currency/presentation/currency_picker.dart';

/// My accounts › an account's currency: the currency its messages and the
/// amounts typed into it are recorded in.
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
    if (code == account.currency) {
      navigator.pop();
      return;
    }
    final repository = ref.read(accountsRepositoryProvider);
    final own = await repository.ownCurrencyTransactions(account.id);
    if (!context.mounted) return;
    if (own.count > 0) {
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
              count: own.count,
              latest: own.latest,
            ),
          ),
        ),
      );
      if (confirmed != true) return;
    }
    await repository.setCurrency(account.id, code);
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

/// Count an account in another currency? Its amounts stay, marked [to].
class _ChangeCurrencySheet extends StatelessWidget {
  const _ChangeCurrencySheet({
    required this.account,
    required this.to,
    required this.base,
    required this.count,
    required this.latest,
  });

  final Account account;
  final String to;
  final String base;
  final int count;
  final TransactionRecord? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final from = account.currency;
    final one = count == 1;
    final marked = one
        ? 'Its 1 transaction keeps its amount and is marked $to'
        : 'Its $count transactions keep their amounts and are marked $to';
    final body = account.institutionId == null
        ? '$marked. New ones you add count in $to.'
        : "$marked, as ${account.name}'s messages show "
              '${one ? 'it' : 'them'}. New messages from ${account.name} count '
              'in $to.';
    final latest = this.latest;

    return Column(
      key: const Key('account-currency-change'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Count ${account.name} in $to?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 14),
        Text(body, style: theme.textTheme.bodyLarge),
        if (latest != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'FOR EXAMPLE',
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: colors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        latest.counterpartyName ??
                            shortDate(CalendarDate.local(latest.occurredAt)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_amount(latest.amountMinor, from)} → '
                      '${_amount(_rescaled(latest.amountMinor, from), to)}',
                      key: const Key('account-currency-example'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Totals in your base currency, $base, change to match.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('account-currency-mark'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(one ? 'Mark it $to' : 'Mark them $to'),
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

  int _rescaled(int minor, String from) => rescaleMinor(
    minor,
    fromDigits: minorUnitDigits(from),
    toDigits: minorUnitDigits(to),
  );

  static String _amount(int minor, String currency) => formatMoney(
    Money(minor.abs(), currency: currency),
    alwaysShowMinorUnits: true,
  );
}
