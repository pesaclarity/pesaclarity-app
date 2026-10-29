import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/categories/default_categories.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Categories: the seeded Kenyan set plus any the user adds.
abstract interface class CategoriesRepository {
  Stream<List<Category>> watchAll();

  /// Creates a category, or returns the id of one with the same name
  /// (ignoring case and spacing). Throws [ArgumentError] for an empty or
  /// over-long name.
  Future<int> create({
    required String name,
    required CategoryType type,
    bool isDailySpending = false,
  });

  /// Creates a category from a transaction, as [create], and sets it as
  /// that transaction's override. Returns the category id.
  Future<int> createForTransaction(
    int transactionId, {
    required String name,
    required CategoryType type,
    bool isDailySpending = false,
  });

  /// Sets or, with null, clears a transaction's category override. Without
  /// one the transaction follows its payee's default category.
  Future<void> setOverride(int transactionId, int? categoryId);

  /// The category with a seeded [key], such as a categoriser label. Null for
  /// [uncategorisedKey] and for keys the user's set no longer has.
  Future<Category?> byKey(String key);

  /// How many transactions each category holds, by id: the person's own
  /// choice, else the payee's, else the automatic one. Updates as
  /// transactions or payees change.
  Stream<Map<int, int>> watchUsage();
}

class DriftCategoriesRepository implements CategoriesRepository {
  DriftCategoriesRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Category>> watchAll() => (_db.select(
    _db.categories,
  )..orderBy([(c) => OrderingTerm(expression: c.name)])).watch();

  @override
  Future<int> create({
    required String name,
    required CategoryType type,
    bool isDailySpending = false,
  }) => _db.transaction(() async {
    final clean = cleanCategoryName(name);
    if (clean == null) {
      throw ArgumentError.value(name, 'name', 'must be 1 to 60 characters');
    }
    final wanted = categoryNameKey(clean);
    for (final c in await _db.select(_db.categories).get()) {
      if (categoryNameKey(c.name) == wanted) return c.id;
    }
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: clean,
            type: type,
            isDailySpending: Value(isDailySpending),
          ),
        );
  });

  @override
  Future<int> createForTransaction(
    int transactionId, {
    required String name,
    required CategoryType type,
    bool isDailySpending = false,
  }) => _db.transaction(() async {
    final id = await create(
      name: name,
      type: type,
      isDailySpending: isDailySpending,
    );
    await setOverride(transactionId, id);
    return id;
  });

  @override
  Future<void> setOverride(int transactionId, int? categoryId) async {
    final updated =
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(transactionId))).write(
          TransactionsCompanion(categoryOverrideId: Value(categoryId)),
        );
    if (updated == 0) {
      throw ArgumentError.value(transactionId, 'transactionId', 'not found');
    }
  }

  @override
  Future<Category?> byKey(String key) => (_db.select(
    _db.categories,
  )..where((c) => c.key.equals(key))).getSingleOrNull();

  @override
  Stream<Map<int, int>> watchUsage() => _db
      .customSelect(
        'SELECT COALESCE(t.category_override_id, p.default_category_id, '
        't.auto_category_id) AS category, COUNT(*) AS uses '
        'FROM transactions t LEFT JOIN payees p ON p.id = t.payee_id '
        'GROUP BY category',
        readsFrom: {_db.transactions, _db.payees},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            ?row.read<int?>('category'): row.read<int>('uses'),
        },
      );
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => DriftCategoriesRepository(ref.watch(appDatabaseProvider)),
);
