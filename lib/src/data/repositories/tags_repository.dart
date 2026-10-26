import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/tags/tag_totals.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Tags say what a transaction is part of (#roadtrip, #reimbursable). They
/// are separate from categories and a transaction can have any number.
abstract interface class TagsRepository {
  Stream<List<Tag>> watchAll();

  /// The id of the tag called [name] after [cleanTagName], creating it if
  /// needed. Throws [ArgumentError] for an empty or over-long name.
  Future<int> findOrCreate(String name);

  Future<void> tag(int transactionId, int tagId);

  Future<void> untag(int transactionId, int tagId);

  Future<List<Tag>> tagsOf(int transactionId);
}

class DriftTagsRepository implements TagsRepository {
  DriftTagsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Tag>> watchAll() => (_db.select(
    _db.tags,
  )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();

  @override
  Future<int> findOrCreate(String name) => _db.transaction(() async {
    final clean = cleanTagName(name);
    if (clean == null) {
      throw ArgumentError.value(name, 'name', 'must be 1 to 40 characters');
    }
    final existing = await (_db.select(
      _db.tags,
    )..where((t) => t.name.equals(clean))).getSingleOrNull();
    return existing?.id ??
        _db.into(_db.tags).insert(TagsCompanion.insert(name: clean));
  });

  @override
  Future<void> tag(int transactionId, int tagId) => _db
      .into(_db.transactionTags)
      .insert(
        TransactionTagsCompanion.insert(
          transactionId: transactionId,
          tagId: tagId,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  @override
  Future<void> untag(int transactionId, int tagId) =>
      (_db.delete(_db.transactionTags)..where(
            (l) =>
                l.transactionId.equals(transactionId) & l.tagId.equals(tagId),
          ))
          .go();

  @override
  Future<List<Tag>> tagsOf(int transactionId) {
    final query =
        _db.select(_db.tags).join([
            innerJoin(
              _db.transactionTags,
              _db.transactionTags.tagId.equalsExp(_db.tags.id),
            ),
          ])
          ..where(_db.transactionTags.transactionId.equals(transactionId))
          ..orderBy([OrderingTerm.asc(_db.tags.name)]);
    return query.map((row) => row.readTable(_db.tags)).get();
  }
}

final tagsRepositoryProvider = Provider<TagsRepository>(
  (ref) => DriftTagsRepository(ref.watch(appDatabaseProvider)),
);
