import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/currency_data.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../domain/accounts/account_reference.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../domain/institution.dart';
import 'account_currency_screen.dart';

/// Profile › My accounts: each account and the currency it counts in, and
/// the way to add or remove accounts.
class MyAccountsSettingsScreen extends ConsumerWidget {
  const MyAccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final base =
        ref.watch(currencyControllerProvider).value?.base ?? BaseCurrency.code;
    final loaded = ref.watch(activityAccountsProvider);
    final accounts = [...?loaded.value?.values]
      ..sort((a, b) => a.id.compareTo(b.id));
    final institutions = {
      for (final i in ref.watch(institutionCatalogueProvider)) i.id: i,
    };

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleProfileMyAccounts,
          child: const Text('My accounts'),
        ),
      ),
      body: !loaded.hasValue
          ? loaded.hasError
                ? ErrorView(
                    'Your accounts could not load.',
                    onRetry: () => ref.invalidate(activityAccountsProvider),
                  )
                : const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  'Each amount keeps the currency its message shows. Totals add '
                  'them up in your base currency, $base.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, account) in accounts.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _AccountRow(
                            account: account,
                            from: _fromLine(account, institutions),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Notice(
                  'Accounts at the same bank are told apart by the account number '
                  'in their messages. Each counts in the currency its messages '
                  'show.',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Semantics(
                    identifier: SemanticIds.myAccountsChoose,
                    child: ListTile(
                      key: const Key('choose-accounts'),
                      title: const Text('Add or remove accounts'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.chooseAccounts),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// `Account 0170…4321` once its messages show a number, `Messages from
/// MPESA` before, or `Money you add by hand` for an account no messages
/// feed.
String _fromLine(Account account, Map<String, Institution> institutions) {
  final institution = institutions[account.institutionId];
  if (account.institutionId == null) return 'Money you add by hand';
  final number = AccountReference.tryParse(account.reference);
  if (number != null) return 'Account ${number.label}';
  if (institution == null) return account.name;
  final senders = institution.senderIds;
  return 'Messages from ${senders.isEmpty ? institution.name : senders.join(', ')}';
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.from});

  final Account account;
  final String from;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final name = currencyCatalogue[account.currency]?.name ?? account.currency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  from,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (account.institutionId != null)
            // Its messages say which currency it is in.
            Semantics(
              label: '${account.name} counts in $name, from its messages',
              excludeSemantics: true,
              child: Tag(
                account.currency,
                key: Key('account-currency-${account.id}'),
              ),
            )
          else
            Semantics(
              button: true,
              label: '${account.name} currency: $name. Change',
              excludeSemantics: true,
              child: OutlinedButton(
                key: Key('account-currency-${account.id}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AccountCurrencyScreen(accountId: account.id),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(account.currency, style: theme.textTheme.labelLarge),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
