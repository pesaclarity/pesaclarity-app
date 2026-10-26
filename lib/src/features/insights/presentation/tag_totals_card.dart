import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/tags_repository.dart';
import '../../../domain/tags/tag_totals.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/pesa_colors.dart';
import '../../export/application/export_service.dart';
import '../../export/presentation/export_sheet.dart';
import '../../payees/application/payee_providers.dart';
import '../application/tag_totals_provider.dart';

/// Insights: spending per tag this month, largest first, with an export.
class TagTotalsSection extends ConsumerWidget {
  const TagTotalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final totals = ref.watch(tagTotalsThisMonthProvider).value;
    final names = {
      for (final u in ref.watch(tagUsageProvider).value ?? const <TagUse>[])
        u.tag.id: u.tag.name,
    };
    final month = YearMonth.nairobi(ref.watch(clockProvider)());
    final monthName = _monthNames[month.month - 1];

    final rows = (totals?.values.toList() ?? <TagSummary>[])
      ..sort(
        (a, b) => b.totals.spendingMinor.compareTo(a.totals.spendingMinor),
      );
    final largest = rows.isEmpty ? 0 : rows.first.totals.spendingMinor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tags in $monthName',
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Export tags',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => showExportSheet(
                context,
                TagTotalsExport(
                  title: 'Tags, $monthName ${month.year}',
                  from: month.startInstant,
                  to: month.endInstant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: rows.isEmpty
                ? Text(
                    'Tag a transaction, like #roadtrip or #wedding, to see '
                    'what it adds up to here.',
                    style: theme.textTheme.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, s) in rows.indexed) ...[
                        if (i > 0) const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '#${names[s.tagId] ?? s.tagId}',
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            Text(
                              formatMoney(
                                Money(s.totals.spendingMinor),
                                withCurrency: false,
                              ),
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: s.totals.spendingMinor <= 0 || largest <= 0
                                ? 0
                                : s.totals.spendingMinor / largest,
                            minHeight: 8,
                            backgroundColor: colors.border,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.entryCount == 1
                              ? '1 transaction'
                              : '${s.entryCount} transactions',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
