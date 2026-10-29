import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/categoriser/features.dart';
import '../../domain/categoriser/learning.dart';
import '../../domain/categoriser/suggester.dart';
import '../../domain/ledger/ledger_entry.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// The person's category choices: corrections the suggester reads first,
/// and a log of confirmations kept on the phone for learning.
abstract interface class CategorySuggestionsRepository {
  /// Category ids by payee key (see `payeeKeys`).
  Stream<Map<String, int>> watchCorrections();

  /// Sets [entry]'s category to [categoryId], remembers it for the payee
  /// and logs whether it matched [suggestion].
  Future<void> confirm(
    LedgerEntry entry, {
    required int categoryId,
    required DateTime at,
    CategorySuggestion? suggestion,
  });

  /// Confirmations whose category has a categoriser key, oldest first.
  Future<List<TrainingExample>> trainingExamples();
}

class DriftCategorySuggestionsRepository
    implements CategorySuggestionsRepository {
  DriftCategorySuggestionsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<Map<String, int>> watchCorrections() => _db
      .select(_db.categoryCorrections)
      .watch()
      .map((rows) => {for (final r in rows) r.payeeKey: r.categoryId});

  @override
  Future<void> confirm(
    LedgerEntry entry, {
    required int categoryId,
    required DateTime at,
    CategorySuggestion? suggestion,
  }) => _db.transaction(() async {
    final updated =
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(entry.id))).write(
          TransactionsCompanion(categoryOverrideId: Value(categoryId)),
        );
    if (updated == 0) {
      throw ArgumentError.value(entry.id, 'entry', 'transaction not found');
    }
    for (final key in payeeKeys(entry)) {
      await _db
          .into(_db.categoryCorrections)
          .insertOnConflictUpdate(
            CategoryCorrectionsCompanion.insert(
              payeeKey: key,
              categoryId: categoryId,
              updatedAt: at,
            ),
          );
    }
    if (entry.payeeId != null) {
      await (_db.update(_db.transactions)..where(
            (t) =>
                t.payeeId.equals(entry.payeeId!) &
                t.categoryOverrideId.isNull(),
          ))
          .write(
            TransactionsCompanion(
              autoCategoryId: Value(categoryId),
              autoCategorySource: const Value(SuggestionSource.correction),
              autoCategoryConfidence: const Value(1.0),
            ),
          );
    }
    await _db
        .into(_db.categoryConfirmations)
        .insert(
          CategoryConfirmationsCompanion.insert(
            transactionId: Value(entry.id),
            categoryId: categoryId,
            suggestedCategoryId: Value(suggestion?.categoryId),
            suggestedConfidence: Value(suggestion?.confidence),
            suggestionSource: Value(suggestion?.source),
            accepted: suggestion?.categoryId == categoryId,
            features: encodeFeatures(categoriserInput(entry).features)
                .join(','),
            featureSchemaVersion: featureSchemaVersion,
            confirmedAt: at,
          ),
        );
  });

  @override
  Future<List<TrainingExample>> trainingExamples() async {
    final c = _db.categoryConfirmations;
    final rows =
        await (_db.select(c).join([
                innerJoin(
                  _db.categories,
                  _db.categories.id.equalsExp(c.categoryId),
                ),
              ])
              ..where(_db.categories.key.isNotNull())
              ..orderBy([OrderingTerm.asc(c.confirmedAt)]))
            .get();
    return [
      for (final row in rows)
        TrainingExample(
          features: [
            for (final v in row.readTable(c).features.split(',')) int.parse(v),
          ],
          label: row.readTable(_db.categories).key!,
          featureSchemaVersion: row.readTable(c).featureSchemaVersion,
        ),
    ];
  }
}

final categorySuggestionsRepositoryProvider =
    Provider<CategorySuggestionsRepository>(
      (ref) =>
          DriftCategorySuggestionsRepository(ref.watch(appDatabaseProvider)),
    );
