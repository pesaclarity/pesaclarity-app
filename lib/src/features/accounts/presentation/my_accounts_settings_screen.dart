import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/currency_data.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../sales/presentation/pay_sheet.dart' show InfoNote;
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
    final accounts = [...?ref.watch(activityAccountsProvider).value?.values]
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Each account counts in its own currency. Totals add them up in '
            'your base currency, $base.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
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
          const InfoNote(
            'Messages from an account are recorded in its currency. Each '
            'account starts in the currency its messages usually use.',
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

/// `Messages from MPESA`, or `Money you add by hand` for an account no
/// messages feed.
String _fromLine(Account account, Map<String, Institution> institutions) {
  final institution = institutions[account.institutionId];
  if (institution == null) return 'Money you add by hand';
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
                  builder: (_) => AccountCurrencyScreen(accountId: account.id),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.currency,
                    style: theme.textTheme.labelLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
