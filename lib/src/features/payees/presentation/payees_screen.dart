import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/categories/default_categories.dart';
import '../../../domain/enums.dart';
import '../../../domain/export/export_tables.dart';
import '../../../theme/pesa_colors.dart';
import '../../export/application/export_service.dart';
import '../../export/presentation/export_sheet.dart';
import '../application/payee_providers.dart';
import 'payee_sheet.dart';

/// Profile > Payees: numbers waiting for a name, and the payees named so
/// far with the category and leak type each applies.
class PayeesScreen extends ConsumerWidget {
  const PayeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final unnamed = ref.watch(unnamedPartiesProvider).value ?? const [];
    final named = ref.watch(payeeSummariesProvider).value ?? const [];

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium!.copyWith(
          color: colors.textMuted,
          letterSpacing: 1,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payees'),
        actions: [ExportButton(scope: () => const PayeesExport())],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'Name a number or till once. Its category and leak type then '
            'apply to every payment, past and future.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
          if (unnamed.isNotEmpty) ...[
            heading('To name'),
            Card(
              child: Column(
                children: [
                  for (final (i, party) in unnamed.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(party.printedName ?? party.identifier.label),
                      subtitle: Text(
                        [
                          if (party.printedName != null) party.identifier.label,
                          _paymentsLabel(party.transactionCount),
                          if (party.outMinor > 0)
                            '${formatMoney(Money(party.outMinor))} out',
                        ].join(' · '),
                      ),
                      trailing: Text(
                        'Name',
                        style: theme.textTheme.labelLarge!.copyWith(
                          color: colors.link,
                        ),
                      ),
                      onTap: () => showPayeeSheet(
                        context,
                        identifier: party.identifier,
                        suggestedName: party.printedName,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          heading('Named'),
          if (named.isEmpty)
            Text(
              'Payees you name show here.',
              style: theme.textTheme.bodyMedium,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final (i, s) in named.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(s.payee.displayName),
                      subtitle: Text(
                        [
                          s.categoryName ?? uncategorisedName,
                          if (s.payee.leakType != LeakType.none)
                            '${leakTypeLabel(s.payee.leakType)} leak',
                          _paymentsLabel(s.transactionCount),
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showPayeeSheet(context, payee: s.payee),
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

String _paymentsLabel(int count) =>
    count == 1 ? '1 transaction' : '$count transactions';
