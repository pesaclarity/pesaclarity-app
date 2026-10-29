import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/enums.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../application/payee_providers.dart';
import 'category_picker.dart';
import 'payee_sheet.dart';
import 'tag_editor.dart';

/// Opens the detail sheet for one transaction, where its payee is named,
/// its category set and its tags edited.
Future<void> showTransactionSheet(BuildContext context, int transactionId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
      AsyncData() => const Center(child: Text('This transaction is gone.')),
      AsyncError() => const Center(child: Text('Could not open it.')),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.detail, this.controller);

  final TransactionDetail detail;
  final ScrollController? controller;

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    final payee = detail.payee;
    final choice = await pickCategory(
      context,
      selectedId: detail.category?.id,
      payeeName: payee?.displayName,
      payeeCategoryName: detail.isCategoryOverridden && payee != null
          ? detail.payeeCategory?.name ?? uncategorisedName
          : null,
    );
    final repo = ref.read(categoriesRepositoryProvider);
    switch (choice) {
      case null:
        return;
      case FollowPayeeCategory():
        await repo.setOverride(detail.record.id, null);
      case ChosenCategory(:final id):
        // Choosing what the payee already gives keeps following the payee.
        final followsPayee = payee != null && id == payee.defaultCategoryId;
        await repo.setOverride(detail.record.id, followsPayee ? null : id);
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
    final amount = formatMoney(
      Money(isIn ? r.amountMinor : -r.amountMinor, currency: r.currency),
    );
    final title =
        payee?.displayName ??
        r.counterpartyName ??
        counterparty?.label ??
        kindLabel(r.kind ?? TransactionKind.bank);
    final categoryNote = detail.isCategoryOverridden
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
        Text(title, style: theme.textTheme.titleLarge),
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
          style: AppTypography.amount(
            size: 32,
            color: isIn ? colors.successText : theme.colorScheme.onSurface,
          ),
        ),
        if (r.feeMinor > 0)
          Text(
            'Fee ${formatMoney(Money(r.feeMinor, currency: r.currency))}',
            style: theme.textTheme.bodySmall,
          ),
        if (r.transferPairId != null)
          Text('Own transfer, not spending', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
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
              ListTile(
                title: const Text('Category'),
                subtitle: Text(
                  [
                    detail.category?.name ?? uncategorisedName,
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
        TransactionTagsEditor(transactionId: r.id),
        if (r.receiptNo != null) ...[
          const SizedBox(height: 20),
          Text('Receipt ${r.receiptNo}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
