import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../data/repositories/payees_repository.dart';
import '../../../data/repositories/purpose_repository.dart';
import '../../../data/repositories/space_move_repository.dart';
import '../../../data/repositories/tax_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/enums.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/lending/loan_link.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/presentation/own_transfer_sheets.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../categoriser/presentation/category_suggestion_sheet.dart';
import '../../currency/presentation/payment_rate_card.dart';
import '../../documents/presentation/receipt_sheet.dart';
import '../../income/presentation/what_was_this_sheet.dart';
import '../../lending/application/lending_providers.dart';
import '../../lending/presentation/loan_from_transaction.dart';
import '../../savings/application/savings_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/payee_providers.dart';
import 'category_picker.dart';
import 'payee_sheet.dart';
import 'tag_editor.dart';

/// Opens the detail sheet for one transaction, where its payee is named,
/// its category set and its tags edited.
Future<void> showTransactionSheet(BuildContext context, int transactionId) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (context, controller) => TransactionSheet(
            transactionId: transactionId,
            controller: controller,
          ),
        ),
      ),
    );

class TransactionSheet extends ConsumerWidget {
  const TransactionSheet({
    required this.transactionId,
    this.controller,
    super.key,
  });

  final int transactionId;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(transactionDetailProvider(transactionId));
    return switch (detail) {
      AsyncData(value: final d?) => _Body(d, controller),
      AsyncData() => const Center(
        child: Text('This transaction was moved or deleted.'),
      ),
      AsyncError() => ErrorView(
        'This transaction could not load.',
        onRetry: () => ref.invalidate(transactionDetailProvider(transactionId)),
      ),
      _ => const LoadingView(),
    };
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.detail, this.controller);

  final TransactionDetail detail;
  final ScrollController? controller;

  /// This transaction as the Lent and borrowed answers see it.
  LoanSubject get _loanSubject {
    final r = detail.record;
    final printed = r.counterpartyName?.trim();
    return LoanSubject(
      transactionId: r.id,
      outflow: r.direction == TransactionDirection.outflow,
      amountMinor: r.amountMinor,
      occurredAt: r.occurredAt,
      currency: r.currency,
      person:
          detail.payee?.displayName ??
          (printed == null || printed.isEmpty ? null : printed),
      canLink:
          r.transferPairId == null &&
          r.transferAccountId == null &&
          r.kind != TransactionKind.correction &&
          !detail.account.type.isBetweenSpaces,
    );
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    final payee = detail.payee;
    final subject = _loanSubject;
    final links = loanLinksFor(ref.read(activeSpaceProvider).kind, subject);
    final linked = ref.read(loanLinksProvider).value?[detail.record.id];
    final choice = await pickCategory(
      context,
      selectedId: detail.category?.id,
      payeeName: payee?.displayName,
      payeeCategoryName: detail.isCategoryOverridden && payee != null
          ? detail.payeeCategory?.name ?? uncategorisedName
          : null,
      loanLinks: links,
      selectedLink: linked?.link,
    );
    if (!context.mounted) return;
    final repo = ref.read(categoriesRepositoryProvider);
    // Money lent chosen from the list is "I lent this" or "Paying me back",
    // so it is linked to its loan too.
    var picked = choice;
    if (choice case ChosenCategory(:final id?) when linked == null) {
      if (await loanLinkOfCategory(repo, links, subject, id) case final l?) {
        picked = LoanChoice(l);
      }
    }
    if (!context.mounted) return;
    switch (picked) {
      case null:
        return;
      case LoanChoice(:final link):
        await linkToLoan(context, subject, link);
      case FollowPayeeCategory():
        await repo.setOverride(detail.record.id, null);
      case ChosenCategory(:final id):
        // Choosing what the payee already gives keeps following the payee,
        // unless money from them asks what it was.
        final followsPayee =
            payee != null &&
            id == payee.defaultCategoryId &&
            !detail.needsPurpose;
        final messenger = ScaffoldMessenger.maybeOf(context);
        final payees = ref.read(payeesRepositoryProvider);
        final categories = ref.read(categoryListProvider).value ?? const [];
        await repo.setOverride(detail.record.id, followsPayee ? null : id);
        if (id != null) {
          await ref
              .read(purposeRepositoryProvider)
              .noteChoice(detail.record.id, id);
        }
        // Only this transaction changes; the payee's others on a tap.
        final name = categories.where((c) => c.id == id).firstOrNull?.name;
        if (payee != null &&
            id != null &&
            name != null &&
            !followsPayee &&
            !detail.needsPurpose &&
            messenger != null) {
          offerUseForPayee(
            messenger,
            category: name,
            payee: payee.displayName,
            onUse: () async {
              await payees.update(payee.id, defaultCategoryId: Value(id));
              await repo.setOverride(detail.record.id, null);
            },
          );
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final r = detail.record;
    final payee = detail.payee;
    final counterparty = detail.counterparty;
    final isIn = r.direction == TransactionDirection.inflow;
    final amount = shownMoney(
      context,
      isIn ? r.amountMinor : -r.amountMinor,
      currency: r.currency,
    );
    final title =
        payee?.displayName ??
        r.counterpartyName ??
        counterparty?.label ??
        kindLabel(r.kind ?? TransactionKind.bank);
    final loan = ref.watch(loanLinksProvider).value?[r.id];
    final categoryNote = loan != null
        ? loanLinkLabel(loan.link, loan.person)
        : detail.isCategoryOverridden
        ? 'Set for this transaction'
        : detail.isCategoryAuto
        ? 'Predicted automatically'
        : payee != null && payee.defaultCategoryId != null
        ? 'From ${payee.displayName}'
        : null;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          [
            formatTimestamp(r.occurredAt),
            detail.account.name,
            kindLabel(r.kind ?? TransactionKind.bank),
          ].join(' · '),
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 12),
        Text(
          amount,
          style: AppTypography.headlineFigure(
            isIn ? colors.successText : theme.colorScheme.onSurface,
          ),
        ),
        BaseAmountLine(r),
        if (r.feeMinor > 0)
          Text(
            'Fee ${shownMoney(context, r.feeMinor, currency: r.currency)}',
            style: theme.textTheme.bodySmall,
          ),
        if (r.transferPairId != null)
          Text('Own transfer, not spending', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        PaymentRateCard(r),
        Card(
          child: Column(
            children: [
              if (payee != null)
                ListTile(
                  title: const Text('Payee'),
                  subtitle: Text(
                    [
                      payee.displayName,
                      if (payee.leakType != LeakType.none)
                        '${leakTypeLabel(payee.leakType)} leak',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showPayeeSheet(context, payee: payee),
                )
              else if (counterparty != null)
                ListTile(
                  title: Text(counterparty.label),
                  subtitle: Text(
                    'Tap to name this payee',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.warning,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showPayeeSheet(
                    context,
                    identifier: counterparty,
                    suggestedName: r.counterpartyName,
                  ),
                ),
              if (payee != null || counterparty != null)
                const Divider(height: 1),
              if (detail.needsPurpose && payee != null) ...[
                ListTile(
                  key: const Key('transaction-what-was-this'),
                  title: const Text('What was this?'),
                  subtitle: const Text(
                    'Their money has meant different things',
                  ),
                  trailing: const TrailingLink('Answer'),
                  onTap: () => showWhatWasThis(
                    context,
                    transactionId: r.id,
                    payeeName: payee.displayName,
                    amountMinor: r.amountMinor,
                    currency: r.currency,
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                title: const Text('Category'),
                subtitle: Text(
                  [
                    detail.category?.name ?? 'Choose later',
                    ?categoryNote,
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickCategory(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OwnMoneySection(r),
        const SizedBox(height: 20),
        TransactionTagsEditor(transactionId: r.id),
        _ShareReceipt(transactionId: r.id),
        _EtimsSwitch(
          transactionId: r.id,
          outflow: r.direction == TransactionDirection.outflow,
        ),
        _MoveToSpace(detail: detail),
        if (r.receiptNo != null) ...[
          const SizedBox(height: 20),
          Text('Receipt ${r.receiptNo}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Switches the transaction to another space, when there is one (decision
/// 0027, section 2): from then on it shows only in the space chosen. On a
/// business's own account, a payment out also offers "This was for me"
/// (section 6).
class _MoveToSpace extends ConsumerWidget {
  const _MoveToSpace({required this.detail});

  final TransactionDetail detail;

  int get transactionId => detail.record.id;

  /// What the switch does, under the list of spaces.
  String? get _switchNote {
    final account = detail.account;
    if (account.institutionId == null ||
        account.type.isBetweenSpaces ||
        detail.record.source == TransactionSource.manual &&
            detail.record.balanceAfterMinor == null) {
      return 'It will show only in the space you choose.';
    }
    return "It will show only in the space you choose. ${account.name}'s "
        'balance here stays as it is.';
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<Space> others,
  ) async {
    final note = _switchNote;
    final target = await showAppSheet<Space>(
      context: context,
      builder: (context) => SheetBody(
        title: 'Switch to',
        children: [
          for (final space in others)
            ListTile(
              key: Key('move-to-${space.id}'),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(space.initial)),
              title: Text(space.name),
              subtitle: Text(space.kind.label),
              onTap: () => Navigator.of(context).pop(space),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                note,
                key: const Key('move-to-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    await ref.read(spaceMoveRepositoryProvider).move(transactionId, target.id);
    navigator.pop();
    // The sheet closes with the switch, so the note goes to the screen
    // below.
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Moved to ${target.name}.')));
  }

  Future<void> _forMe(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    await ref.read(spaceMoveRepositoryProvider).forMe(transactionId);
    navigator.pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Paid yourself. It shows in Personal as yours.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider).value ?? const [];
    final active = ref.watch(activeSpaceProvider);
    final others = [
      for (final s in spaces)
        if (s.id != active.id) s,
    ];
    // A savings app's entries stay with it (its page can remove it).
    final savings = ref.watch(savingsEntryProvider(transactionId)).value;
    if (others.isEmpty || savings != null) return const SizedBox.shrink();
    final record = detail.record;
    // A side of Pay yourself, or a correction of another space's part,
    // belongs to the pair.
    if (detail.account.type == AccountType.heldForSpace) {
      return const SizedBox.shrink();
    }
    final forMe =
        active.kind == SpaceKind.business &&
        record.direction == TransactionDirection.outflow &&
        !detail.account.type.isBetweenSpaces &&
        record.linkId == null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (forMe) ...[
            OutlinedButton.icon(
              key: const Key('transaction-for-me'),
              icon: const Icon(Icons.person_outline),
              label: const Text('This was for me'),
              onPressed: () => _forMe(context, ref),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const Key('transaction-move-space'),
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('Switch to another space'),
            onPressed: () => _move(context, ref, others),
          ),
        ],
      ),
    );
  }
}

/// The sale a business's money came from, for sharing its receipt again.
final _saleOfTransactionProvider = FutureProvider.family<int?, int>(
  (ref, transactionId) =>
      ref.watch(documentsRepositoryProvider).saleOf(transactionId),
);

class _ShareReceipt extends ConsumerWidget {
  const _ShareReceipt({required this.transactionId});

  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeSpaceProvider).kind != SpaceKind.business) {
      return const SizedBox.shrink();
    }
    final saleId = ref.watch(_saleOfTransactionProvider(transactionId)).value;
    if (saleId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        key: const Key('transaction-receipt'),
        icon: const Icon(Icons.ios_share),
        label: const Text('Share receipt'),
        onPressed: () => showReceiptSheet(context, saleId, justSaved: false),
      ),
    );
  }
}

/// Whether a business's cost has an eTIMS invoice, for the Tax screen.
final _etimsProvider = FutureProvider<Set<int>>((ref) {
  ref.watch(ledgerChangesProvider);
  return ref.watch(taxRepositoryProvider).etimsCosts();
});

class _EtimsSwitch extends ConsumerWidget {
  const _EtimsSwitch({required this.transactionId, required this.outflow});

  final int transactionId;
  final bool outflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!outflow || ref.watch(activeSpaceProvider).kind != SpaceKind.business) {
      return const SizedBox.shrink();
    }
    final has = ref.watch(_etimsProvider).value?.contains(transactionId);
    if (has == null) return const SizedBox.shrink();
    return SwitchListTile.adaptive(
      key: const Key('transaction-etims'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Has an eTIMS invoice'),
      subtitle: const Text('KRA asks for one for a cost to count for tax'),
      value: has,
      onChanged: (on) =>
          ref.read(taxRepositoryProvider).setEtims(transactionId, has: on),
    );
  }
}
