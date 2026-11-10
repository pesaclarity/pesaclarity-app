import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/categories/default_categories.dart';
import '../../../domain/enums.dart';
import '../../../domain/export/export_tables.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
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
    final unnamedAsync = ref.watch(unnamedPartiesProvider);
    final namedAsync = ref.watch(payeeSummariesProvider);
    final unnamed = unnamedAsync.value ?? const [];
    final named = namedAsync.value ?? const [];

    final appBar = AppBar(
      title: const Text('Payees'),
      actions: [
        ExportButton(scope: () => const PayeesExport()),
        const AmountsEye(),
        const SizedBox(width: 8),
      ],
    );
    if ((unnamedAsync.hasError && !unnamedAsync.hasValue) ||
        (namedAsync.hasError && !namedAsync.hasValue)) {
      return Scaffold(
        appBar: appBar,
        body: ErrorView(
          'Payees could not load.',
          onRetry: () => ref
            ..invalidate(unnamedPartiesProvider)
            ..invalidate(payeeSummariesProvider),
        ),
      );
    }
    if (!unnamedAsync.hasValue || !namedAsync.hasValue) {
      return Scaffold(appBar: appBar, body: const LoadingView());
    }

    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Name a number or till once. Its category and leak type then '
            'apply to every payment, past and future.',
            style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
          ),
          if (unnamed.isNotEmpty) ...[
            const SectionLabel('To name'),
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
                            '${shownMoney(context, party.outMinor)} out',
                        ].join(' · '),
                      ),
                      trailing: const TrailingLink('Name'),
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
          const SectionLabel('Named'),
          if (named.isEmpty)
            const EmptyNote('Payees you name show here.')
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
