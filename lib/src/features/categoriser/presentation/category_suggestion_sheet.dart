import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../payees/presentation/category_picker.dart';
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

/// Opens the sheet to accept [suggestion] for [entry], or the category
/// picker to choose one, the same picker as everywhere else. With no
/// suggestion, the picker opens straight away.
Future<void> showCategorySuggestionSheet(
  BuildContext context, {
  required LedgerEntry entry,
  required String title,
  CategorySuggestion? suggestion,
}) async {
  if (suggestion == null) {
    final container = ProviderScope.containerOf(context);
    final choice = await _pickFor(context, entry);
    if (choice case ChosenCategory(:final id?)) {
      await container
          .read(categorySuggestionsRepositoryProvider)
          .confirm(entry, categoryId: id, at: container.read(clockProvider)());
    }
    return;
  }
  await showAppSheet<void>(
    context: context,
    builder: (context) => CategorySuggestionSheet(
      entry: entry,
      title: title,
      suggestion: suggestion,
    ),
  );
}

/// The category picker for [entry]: income categories for money in,
/// spending ones for money out.
Future<CategoryChoice?> _pickFor(
  BuildContext context,
  LedgerEntry entry, {
  int? selectedId,
}) => pickCategory(
  context,
  selectedId: selectedId,
  allowType: (t) =>
      entry.isInflow ? t != CategoryType.expense : t != CategoryType.income,
);

/// Shows the suggested category with its confidence: one tap accepts it,
/// and Change opens the category picker.
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
  var _saving = false;

  Future<void> _save(int categoryId) async {
    if (_saving) return;
    setState(() => _saving = true);
    await confirmCategory(ref, widget.entry, categoryId, widget.suggestion);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _change(int? suggestedId) async {
    final choice = await _pickFor(
      context,
      widget.entry,
      selectedId: suggestedId,
    );
    if (choice case ChosenCategory(:final id?)) await _save(id);
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
    return SheetBody(
      title: widget.title,
      subtitle: shownMoney(context, entry.signedMinor),
      children: [
        if (suggestion != null && suggested != null) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel(
                    'Suggested category',
                    padding: EdgeInsets.only(bottom: 6),
                  ),
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
          ButtonPair(
            primary: FilledButton(
              key: const Key('category-accept'),
              onPressed: _saving ? null : () => _save(suggested.id),
              child: const Text('Accept'),
            ),
            secondary: OutlinedButton(
              key: const Key('category-change'),
              onPressed: _saving ? null : () => _change(suggested.id),
              child: const Text('Change'),
            ),
          ),
        ],
      ],
    );
  }
}
