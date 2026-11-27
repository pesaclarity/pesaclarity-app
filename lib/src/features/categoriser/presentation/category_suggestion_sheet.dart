import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/category_suggestions_repository.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/lending/loan_link.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../lending/presentation/loan_from_transaction.dart';
import '../../payees/presentation/category_picker.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/categoriser_providers.dart';

/// Short line on where a suggestion came from.
String suggestionSourceLabel(SuggestionSource source) => switch (source) {
  SuggestionSource.correction => 'Your earlier choice for this payee',
  SuggestionSource.model => 'Suggested on this phone',
  SuggestionSource.rules => 'Based on the payee and message type',
};

/// Sets [entry]'s category to [categoryId], for that transaction only,
/// then offers to use it for all of the payee's transactions.
Future<void> confirmCategory(
  BuildContext context,
  LedgerEntry entry,
  int categoryId,
  CategorySuggestion? suggestion,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  await container
      .read(categorySuggestionsRepositoryProvider)
      .confirm(
        entry,
        categoryId: categoryId,
        at: container.read(clockProvider)(),
        suggestion: suggestion,
      );
  final payee = entry.payeeName ?? entry.counterpartyName;
  final categories = container.read(categoryListProvider).value ?? const [];
  final category = categories.where((c) => c.id == categoryId).firstOrNull;
  final sameParty =
      entry.payeeId != null ||
      (entry.counterpartyKind != null && entry.counterpartyValue != null);
  if (messenger == null || payee == null || category == null || !sameParty) {
    return;
  }
  offerUseForPayee(
    messenger,
    category: category.name,
    payee: payee,
    onUse: () => container
        .read(categorySuggestionsRepositoryProvider)
        .useForPayee(
          entry,
          categoryId: categoryId,
          at: container.read(clockProvider)(),
        ),
  );
}

/// "Use Food for all Tamu Tamu transactions?": a note whose action runs
/// [onUse]. Nothing changes for the payee's other transactions unless it is
/// tapped.
void offerUseForPayee(
  ScaffoldMessengerState messenger, {
  required String category,
  required String payee,
  required VoidCallback onUse,
}) {
  if (payee.trim().isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Use $category for all $payee transactions?'),
        action: SnackBarAction(label: 'Use for all', onPressed: onUse),
      ),
    );
}

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
    final choice = await _pickFor(context, entry);
    if (!context.mounted) return;
    if (await _loanOf(context, entry, choice) case final link?) {
      if (context.mounted) {
        await linkToLoan(context, loanSubjectOf(entry), link);
      }
      return;
    }
    if (choice case ChosenCategory(:final id?)) {
      if (context.mounted) await confirmCategory(context, entry, id, null);
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

/// What [entry] can be in Lent and borrowed in the open space.
List<LoanLink> _loanLinks(BuildContext context, LedgerEntry entry) =>
    loanLinksFor(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(activeSpaceProvider).kind,
      loanSubjectOf(entry),
    );

/// The category picker for [entry]: income categories for money in,
/// spending ones for money out, and in a Personal-style space what it can
/// be in Lent and borrowed.
Future<CategoryChoice?> _pickFor(
  BuildContext context,
  LedgerEntry entry, {
  int? selectedId,
}) => pickCategory(
  context,
  selectedId: selectedId,
  allowType: (t) =>
      entry.isInflow ? t != CategoryType.expense : t != CategoryType.income,
  loanLinks: _loanLinks(context, entry),
);

/// The loan [choice] makes [entry]: one of Lent and borrowed's answers, or
/// Money lent picked from the list. Null for any other category.
Future<LoanLink?> _loanOf(
  BuildContext context,
  LedgerEntry entry,
  CategoryChoice? choice,
) async => switch (choice) {
  LoanChoice(:final link) => link,
  ChosenCategory(:final id?) => loanLinkOfCategory(
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(categoriesRepositoryProvider),
    _loanLinks(context, entry),
    loanSubjectOf(entry),
    id,
  ),
  _ => null,
};

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
    await confirmCategory(context, widget.entry, categoryId, widget.suggestion);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _change(int? suggestedId) async {
    final choice = await _pickFor(
      context,
      widget.entry,
      selectedId: suggestedId,
    );
    if (!mounted) return;
    if (await _loanOf(context, widget.entry, choice) case final link?) {
      if (!mounted) return;
      await linkToLoan(context, loanSubjectOf(widget.entry), link);
      if (mounted) Navigator.pop(context);
      return;
    }
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
