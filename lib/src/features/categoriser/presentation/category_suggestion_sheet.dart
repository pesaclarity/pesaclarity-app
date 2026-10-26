import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../application/categoriser_providers.dart';

/// Short line on where a suggestion came from.
String suggestionSourceLabel(SuggestionSource source) => switch (source) {
  SuggestionSource.correction => 'Your earlier choice for this payee',
  SuggestionSource.model => 'Suggested on this phone',
  SuggestionSource.rules => 'Based on the payee and message type',
};

/// Sets [entry]'s category to [categoryId] and remembers it for its payee.
Future<void> confirmCategory(
  WidgetRef ref,
  LedgerEntry entry,
  int categoryId,
  CategorySuggestion? suggestion,
) => ref
    .read(categorySuggestionsRepositoryProvider)
    .confirm(
      entry,
      categoryId: categoryId,
      at: ref.read(clockProvider)(),
      suggestion: suggestion,
    );

/// Opens the sheet to accept [suggestion] for [entry] or pick another
/// category.
Future<void> showCategorySuggestionSheet(
  BuildContext context, {
  required LedgerEntry entry,
  required String title,
  CategorySuggestion? suggestion,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => CategorySuggestionSheet(
    entry: entry,
    title: title,
    suggestion: suggestion,
  ),
);

/// Shows the suggested category with its confidence: one tap accepts it,
/// Change lists the other categories, and one tap on any of them saves it.
class CategorySuggestionSheet extends ConsumerStatefulWidget {
  const CategorySuggestionSheet({
    required this.entry,
    required this.title,
    this.suggestion,
    super.key,
  });

  final LedgerEntry entry;
  final String title;
  final CategorySuggestion? suggestion;

  @override
  ConsumerState<CategorySuggestionSheet> createState() =>
      _CategorySuggestionSheetState();
}

class _CategorySuggestionSheetState
    extends ConsumerState<CategorySuggestionSheet> {
  late var _choosing = widget.suggestion == null;
  var _saving = false;

  Future<void> _save(int categoryId) async {
    if (_saving) return;
    setState(() => _saving = true);
    await confirmCategory(ref, widget.entry, categoryId, widget.suggestion);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final entry = widget.entry;
    final suggestion = widget.suggestion;
    final all = ref.watch(categoryListProvider).value ?? const <Category>[];
    final byId = {for (final c in all) c.id: c};
    final suggested = suggestion == null ? null : byId[suggestion.categoryId];
    final options = all
        .where(
          (c) => entry.isInflow
              ? c.type != CategoryType.expense
              : c.type != CategoryType.income,
        )
        .toList();
    final amount = formatMoney(Money(entry.signedMinor));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              amount,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            if (suggestion != null && suggested != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUGGESTED CATEGORY',
                        style: theme.textTheme.labelLarge!.copyWith(
                          color: colors.textMuted,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(suggested.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${suggestion.percent}% sure · '
                        '${suggestionSourceLabel(suggestion.source)}',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _choosing = !_choosing),
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(suggested.id),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
            if (_choosing || suggested == null) ...[
              const SizedBox(height: 8),
              Text('Choose a category', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Your choice applies to this payee from now on.',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in options)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name),
                        trailing: c.id == suggested?.id
                            ? Icon(Icons.check, color: colors.link)
                            : null,
                        enabled: !_saving,
                        onTap: () => _save(c.id),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
