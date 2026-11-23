import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/currency_data.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/fuliza_tracking.dart';
import '../../../domain/accounts/account_reference.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../savings/presentation/savings_accounts_card.dart';
import '../../sms/presentation/paste_messages_screen.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/mpesa_family_providers.dart';
import '../application/mpesa_lines_providers.dart';
import '../domain/institution.dart';
import 'account_page.dart';
import 'line_questions.dart';
import 'mpesa_family_card.dart';
import 'mpesa_lines_screen.dart';
import 'mpesa_lines_sheet.dart';
import 'sacco_screens.dart';

/// Profile › My accounts: each account and the currency it counts in, the
/// savings apps the app keeps, such as Chumz, and the way to add or remove
/// accounts.
class MyAccountsSettingsScreen extends ConsumerWidget {
  const MyAccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final base =
        ref.watch(currencyControllerProvider).value?.base ?? BaseCurrency.code;
    final loaded = ref.watch(activityAccountsProvider);
    final lineAccounts = ref.watch(readLineAccountsProvider);
    final hidden = ref.watch(hiddenLineAccountsProvider);
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final readsMpesa = ref.watch(readsMpesaHereProvider).value ?? false;
    final fuliza =
        ref.watch(fulizaTrackingProvider).value ?? FulizaTracking.unseen;
    // M-Pesa with linked accounts is a group of its own (decision 0026).
    final families = <MpesaFamily>[
      for (final f
          in ref.watch(mpesaFamiliesProvider).value ?? const <MpesaFamily>[])
        if (f.hasMembers && !hidden.contains(f.wallet.account.id)) f,
    ];
    final grouped = {
      for (final f in families) ...[
        f.wallet.account.id,
        for (final b in f.business) b.account.id,
      ],
    };
    // A SACCO has a card of its own, with its loan.
    final saccoIds = {
      for (final (a, _)
          in ref.watch(saccosProvider).value ??
              const <(Account, SaccoDetailsRow)>[])
        a.id,
    };
    final named = withLineNames({...?loaded.value}, lineAccounts);
    // Savings apps, such as Chumz, have a card of their own. A line given
    // to another space leaves an empty account here, not shown.
    final accounts = [
      for (final a in named.values)
        if (a.product == null &&
            !a.hidden &&
            !saccoIds.contains(a.id) &&
            !hidden.contains(a.id) &&
            !grouped.contains(a.id))
          a,
    ]..sort(byLineOrder(lines, lineAccounts.keys));
    // Accounts the person hid, still in totals and history.
    final hiddenByPerson = [
      for (final a in named.values)
        if (a.hidden && !hidden.contains(a.id)) a,
    ]..sort((a, b) => a.id.compareTo(b.id));
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
                if (families.isNotEmpty) ...[
                  OwnAndOweCard(families: families),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Each amount keeps the currency its message shows. Totals add '
                  'them up in your base currency, $base.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (readsMpesa && lines.offersSplit && !lines.offerHidden) ...[
                  const SizedBox(height: 16),
                  const _SplitOffer(),
                ],
                for (final f in families) ...[
                  const SizedBox(height: 16),
                  MpesaFamilyCard(
                    family: f,
                    name: named[f.wallet.account.id]?.name ?? 'M-Pesa',
                  ),
                ],
                if (accounts.isNotEmpty) ...[
                  SizedBox(height: families.isEmpty ? 16 : Layout.cardGap),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, account) in accounts.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _AccountRow(
                            account: account,
                            from: _fromLine(
                              context,
                              account,
                              institutions,
                              lineAccounts[account.id],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                // iPhone: messages Shortcuts missed, pasted or from a
                // statement.
                if (readsMpesa && defaultTargetPlatform == TargetPlatform.iOS)
                  const PasteMessagesRows(),
                const SizedBox(height: Layout.cardGap),
                SaccosCard(
                  onOpen: (id) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => SaccoScreen(
                        accountId: id,
                        onEdit: () => openAccountPage(context, id),
                      ),
                    ),
                  ),
                ),
                const SavingsAccountsCard(),
                const SizedBox(height: 12),
                Notice(
                  [
                    'Accounts at the same bank are told apart by the account '
                        'number in their messages.',
                    if (lines.split)
                      lines.bySim
                          ? 'M-Pesa lines are told apart by the SIM their '
                                'messages arrive on.'
                          : 'M-Pesa lines are told apart by the balance each '
                                'message shows.',
                    'Each counts in the currency its messages show.',
                  ].join(' '),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      if (hiddenByPerson.isNotEmpty) ...[
                        ListTile(
                          key: const Key('hidden-accounts'),
                          title: const Text(AccountEditText.hiddenAccounts),
                          subtitle: Text(
                            '${hiddenByPerson.length} hidden · '
                            '${hiddenByPerson.map((a) => a.name).join(', ')}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const HiddenAccountsScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      if (lines.twoSeen) ...[
                        _LinesRow(lines: lines),
                        const Divider(height: 1),
                      ],
                      // Only for people who use Fuliza: kept with the space
                      // its messages are read in.
                      if (fuliza.seen) ...[
                        _TrackFulizaRow(tracked: fuliza.tracked),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        key: const Key('add-sacco'),
                        title: const Text(SaccoText.addSacco),
                        subtitle: const Text(SaccoText.addSaccoHint),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showAddSaccoSheet(context),
                      ),
                      const Divider(height: 1),
                      Semantics(
                        identifier: SemanticIds.myAccountsChoose,
                        child: ListTile(
                          key: const Key('choose-accounts'),
                          title: const Text('Add or remove accounts'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(AppRoutes.chooseAccounts),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// `Account 0170…4321` once its messages show a number, `Messages from
/// MPESA` before, or `Money you add by hand` for an account no messages
/// feed. An M-Pesa line says how it is told apart: `Messages from MPESA ·
/// SIM 1`, or by its balance where the phone reports no SIM.
String _fromLine(
  BuildContext context,
  Account account,
  Map<String, Institution> institutions,
  MpesaLine? line,
) {
  final institution = institutions[account.institutionId];
  if (account.institutionId == null) return 'Money you add by hand';
  final number = AccountReference.tryParse(account.reference);
  if (number != null) return 'Account ${number.label}';
  if (institution == null) return account.name;
  final senders = institution.senderIds;
  final from =
      'Messages from ${senders.isEmpty ? institution.name : senders.join(', ')}';
  if (line == null) return from;
  if (line.sims.isNotEmpty) return '$from · ${line.slot}';
  final balance = line.balanceMinor;
  return balance == null
      ? from
      : '$from · balance ${shownMoney(context, balance, withCurrency: false)}';
}

/// "Two M-Pesa lines on this phone": what is wrong, Split them, and Not
/// now. Nothing is split without asking.
class _SplitOffer extends ConsumerWidget {
  const _SplitOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      key: const Key('lines-offer'),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Two M-Pesa lines on this phone',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Both are read into one M-Pesa account, so their payments are '
              'mixed and the balance jumps between the two.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            ButtonPair(
              primary: FilledButton(
                key: const Key('lines-offer-split'),
                onPressed: () => showMpesaLinesSheet(context),
                child: const Text('Split them'),
              ),
              secondary: OutlinedButton(
                key: const Key('lines-offer-later'),
                onPressed: () =>
                    ref.read(mpesaLinesProvider.notifier).hideOffer(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "M-Pesa lines", once two lines have been seen: where a line given to
/// another space is, and the way to name and move them.
class _LinesRow extends ConsumerWidget {
  const _LinesRow({required this.lines});

  final MpesaLines lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider).value ?? const [Space.personal];
    final names = {for (final s in spaces) s.id: s.name};
    final here = ref.watch(activeSpaceIdProvider);
    final listed = names.keys.toSet();
    final elsewhere = [
      if (lines.split)
        for (final line in lines.lines)
          if (lines.readerOf(line, listed) case final reader
              when reader != here)
            '${line.label} is in ${names[reader] ?? 'Personal'}',
    ];
    return ListTile(
      key: const Key('mpesa-lines'),
      title: const Text('M-Pesa lines'),
      subtitle: Text(
        elsewhere.isEmpty
            ? 'Name them, or give one to a business'
            : elsewhere.join('. '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openMpesaLines(context),
    );
  }
}

/// "Track Fuliza": on, Fuliza shows as a debt on M-Pesa; off, it is hidden
/// everywhere and M-Pesa shows the balance M-Pesa reports. Nothing is lost
/// either way.
class _TrackFulizaRow extends ConsumerWidget {
  const _TrackFulizaRow({required this.tracked});

  final bool tracked;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile.adaptive(
    key: const Key('track-fuliza'),
    value: tracked,
    onChanged: (track) =>
        ref.read(fulizaTrackedProvider.notifier).setTracked(track),
    title: const Text('Track Fuliza'),
    subtitle: Text(
      tracked
          ? 'What you owe Fuliza shows as a debt on M-Pesa'
          : 'Hidden. M-Pesa shows the balance its messages report',
    ),
  );
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
    return Semantics(
      button: true,
      label: '${account.name}, $from, counts in $name. Open',
      excludeSemantics: true,
      child: InkWell(
        key: Key('account-row-${account.id}'),
        onTap: () => openAccountPage(context, account.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
              Tag(account.currency, key: Key('account-currency-${account.id}')),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// My accounts › Hidden accounts: the accounts the person hid from lists.
/// They still count in totals and keep their history; each opens its page,
/// where Hide from lists can be switched off.
class HiddenAccountsScreen extends ConsumerWidget {
  const HiddenAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = [
      for (final a
          in (ref.watch(activityAccountsProvider).value ?? const {}).values)
        if (a.hidden) a,
    ];
    final institutions = {
      for (final i in ref.watch(institutionCatalogueProvider)) i.id: i,
    };
    return Scaffold(
      appBar: AppBar(title: const Text(AccountEditText.hiddenAccounts)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'They still count in totals and keep their history. Open one to '
            'show it again.',
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(color: PesaColors.of(context).textMuted),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            const Text('No hidden accounts.')
          else
            Card(
              child: Column(
                children: [
                  for (final (i, a) in accounts.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _AccountRow(
                      account: a,
                      from: _fromLine(context, a, institutions, null),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
