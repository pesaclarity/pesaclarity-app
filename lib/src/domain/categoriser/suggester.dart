import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import 'categoriser.dart';
import 'features.dart';

/// A category the person can pick, as the suggester needs it.
class CategoryOption {
  const CategoryOption({required this.id, required this.type, this.key});

  final int id;

  /// The seeded key, which categoriser labels map to. Null for categories
  /// the person made.
  final String? key;
  final CategoryType type;
}

/// A suggested category for one transaction.
class CategorySuggestion {
  const CategorySuggestion({
    required this.categoryId,
    required this.confidence,
    required this.source,
    this.key,
  });

  final int categoryId;

  /// The categoriser label behind it, when it came from one.
  final String? key;

  /// From 0 to 1; a person's own earlier choice is 1.
  final double confidence;
  final SuggestionSource source;

  /// Confidence as a whole percentage.
  int get percent => (confidence * 100).round().clamp(0, 100);
}

/// Keys for [entry]'s payee in the correction store, most specific first:
/// the named payee, the raw identifier, then the tokenised name.
List<String> payeeKeys(LedgerEntry entry) {
  final kind = entry.counterpartyKind;
  final value = entry.counterpartyValue;
  final name = tokenise(entry.payeeName ?? entry.counterpartyName ?? '');
  return [
    if (entry.payeeId != null) 'payee:${entry.payeeId}',
    if (kind != null && value != null) 'id:${kind.name}:$value',
    if (name.isNotEmpty) 'name:${name.join(' ')}',
  ];
}

/// What the categoriser reads for [entry].
CategoriserInput categoriserInput(LedgerEntry entry) => CategoriserInput(
  payee:
      entry.counterpartyName ??
      entry.payeeName ??
      entry.counterpartyValue ??
      entry.note ??
      '',
  amountMinor: entry.amountMinor,
  isInflow: entry.isInflow,
  occurredAt: entry.occurredAt,
  kind: entry.kind,
);

const _noCategoryRoles = {
  LedgerRole.ownTransfer,
  LedgerRole.borrowing,
  LedgerRole.awaitingPayee,
  LedgerRole.reversal,
};

/// Whether [entry] has no category and is the kind of line a category is
/// for. Own transfers, borrowing, reversals and unnamed senders are not.
bool needsCategory(LedgerEntry entry) =>
    entry.categoryId == null && !_noCategoryRoles.contains(roleOf(entry));

/// Suggests a category: the person's own choice for the payee first, then
/// the categoriser's best label that maps to one of their categories.
class CategorySuggester {
  CategorySuggester({
    required this.categoriser,
    required Iterable<CategoryOption> categories,
    required this.corrections,
    this.minConfidence = 0.3,
  }) : _byId = {for (final c in categories) c.id: c},
       _byKey = {
         for (final c in categories)
           if (c.key != null) c.key!: c,
       };

  final Categoriser categoriser;
  final Map<int, CategoryOption> _byId;
  final Map<String, CategoryOption> _byKey;

  /// The person's choices: category ids by payee key.
  final Map<String, int> corrections;

  /// Categoriser guesses below this are not shown.
  final double minConfidence;

  /// A suggestion for [entry], or null when nothing fits well enough.
  CategorySuggestion? suggest(LedgerEntry entry) {
    for (final key in payeeKeys(entry)) {
      final chosen = _byId[corrections[key]];
      if (chosen != null && _fits(chosen, entry)) {
        return CategorySuggestion(
          categoryId: chosen.id,
          key: chosen.key,
          confidence: 1,
          source: SuggestionSource.correction,
        );
      }
    }
    for (final score in categoriser.score(categoriserInput(entry))) {
      if (score.confidence < minConfidence) break;
      final option = _byKey[score.key];
      if (option != null && _fits(option, entry)) {
        return CategorySuggestion(
          categoryId: option.id,
          key: score.key,
          confidence: score.confidence,
          source: categoriser.source,
        );
      }
    }
    return null;
  }

  /// Money in never goes to an expense category, money out never to income.
  bool _fits(CategoryOption option, LedgerEntry entry) => entry.isInflow
      ? option.type != CategoryType.expense
      : option.type != CategoryType.income;
}

/// Confidence threshold at or above which an automatic suggestion is applied.
const autoApplyConfidence = 0.6;

/// Whether [suggestion] is confident enough to apply automatically.
bool autoApplies(CategorySuggestion? suggestion) {
  if (suggestion == null) return false;
  return suggestion.source == SuggestionSource.correction ||
      suggestion.confidence >= autoApplyConfidence;
}
