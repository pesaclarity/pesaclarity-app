import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/categories/default_categories.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'loan_links_repository.dart';

/// Categories: the seeded Kenyan set plus any the user adds.
abstract interface class CategoriesRepository {
  Stream<List<Category>> watchAll();

  /// Creates a category, or returns the id of one with the same name
  /// (ignoring case and spacing). Throws [ArgumentError] for an empty or
  /// over-long name.
  ///
  /// With [parentId], creates a subcategory of that top-level category,
  /// which takes its type and day-to-day setting whatever is passed.
  /// Throws [ArgumentError] when the parent is itself a subcategory or is
  /// missing, and [CategoryNameTaken] when the name is used elsewhere. A
  /// top-level category of the same name and type, with no subcategories
  /// or budgets, moves under the parent instead.
  Future<int> create({
    required String name,
    required CategoryType type,
    bool isDailySpending = false,
    int? parentId,
  });

  /// Renames a category. Throws [ArgumentError] for an empty or over-long
  /// name and [CategoryNameTaken] for one another category has.
  Future<void> rename(int id, String name);

  /// Deletes subcategory [id]. Its transactions, payees and budgets move to
  /// its parent, so nothing drops out of the parent's totals. Throws
  /// [ArgumentError] for a top-level category.
  Future<void> deleteSubcategory(int id);

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

/// A category name another category already has. Names are unique
/// across the whole list, subcategories included.
class CategoryNameTaken implements Exception {
  const CategoryNameTaken(this.name);

  /// The name as the other category has it.
  final String name;

  @override
  String toString() => 'There is already a category called $name';
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
    int? parentId,
  }) => _db.transaction(() async {
    final clean = cleanCategoryName(name);
    if (clean == null) {
      throw ArgumentError.value(name, 'name', 'must be 1 to 60 characters');
    }
    final all = await _db.select(_db.categories).get();
    Category? parent;
    if (parentId != null) {
      parent = all.where((c) => c.id == parentId).firstOrNull;
      if (parent == null || parent.parentId != null) {
        throw ArgumentError.value(
          parentId,
          'parentId',
          'must be a top-level category',
        );
      }
    }
    final wanted = categoryNameKey(clean);
    for (final c in all) {
      if (categoryNameKey(c.name) != wanted) continue;
      if (c.parentId == parentId) return c.id;
      // A top-level category of the same kind, such as the seeded Fuel,
      // moves under the parent: its money then adds up there too. Not one
      // with subcategories of its own, or with budgets, which stay on
      // top-level categories.
      if (parent != null &&
          c.parentId == null &&
          c.id != parent.id &&
          c.type == parent.type &&
          !all.any((o) => o.parentId == c.id) &&
          !await _hasBudget(c.id)) {
        await (_db.update(
          _db.categories,
        )..where((r) => r.id.equals(c.id))).write(
          CategoriesCompanion(
            parentId: Value(parent.id),
            isDailySpending: Value(parent.isDailySpending),
          ),
        );
        return c.id;
      }
      throw CategoryNameTaken(c.name);
    }
    return _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: clean,
            type: parent?.type ?? type,
            isDailySpending: Value(parent?.isDailySpending ?? isDailySpending),
            parentId: Value(parentId),
          ),
        );
  });

  Future<bool> _hasBudget(int categoryId) async =>
      await (_db.select(_db.budgetItems)
            ..where((b) => b.categoryId.equals(categoryId))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  @override
  Future<void> rename(int id, String name) => _db.transaction(() async {
    final clean = cleanCategoryName(name);
    if (clean == null) {
      throw ArgumentError.value(name, 'name', 'must be 1 to 60 characters');
    }
    final wanted = categoryNameKey(clean);
    for (final c in await _db.select(_db.categories).get()) {
      if (c.id != id && categoryNameKey(c.name) == wanted) {
        throw CategoryNameTaken(c.name);
      }
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(name: Value(clean)),
    );
  });

  @override
  Future<void> deleteSubcategory(int id) => _db.transaction(() async {
    final sub = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    final parentId = sub?.parentId;
    if (sub == null || parentId == null) {
      throw ArgumentError.value(id, 'id', 'not a subcategory');
    }
    for (final sql in [
      'UPDATE transactions SET category_override_id = ? '
          'WHERE category_override_id = ?',
      'UPDATE transactions SET auto_category_id = ? '
          'WHERE auto_category_id = ?',
      'UPDATE payees SET default_category_id = ? '
          'WHERE default_category_id = ?',
      'UPDATE budget_items SET category_id = ? WHERE category_id = ?',
      'UPDATE recurring SET category_id = ? WHERE category_id = ?',
      // What the categoriser learnt about it now points at the parent.
      'UPDATE OR IGNORE category_corrections SET category_id = ? '
          'WHERE category_id = ?',
      'UPDATE OR IGNORE category_confirmations SET category_id = ? '
          'WHERE category_id = ?',
    ]) {
      await _db.customStatement(sql, [parentId, id]);
    }
    // Month-end results are kept per top-level category already.
    await _db.customStatement(
      'DELETE FROM budget_snapshots WHERE category_id = ?',
      [id],
    );
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
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
  Future<void> setOverride(int transactionId, int? categoryId) =>
      _db.transaction(() async {
        // Another category takes it out of its loan in Lent and borrowed.
        final tx = await (_db.select(
          _db.transactions,
        )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
        if (tx != null && await leavesLoan(_db, tx, categoryId)) {
          await unlinkLoan(_db, transactionId);
        }
        final updated =
            await (_db.update(
              _db.transactions,
            )..where((t) => t.id.equals(transactionId))).write(
              TransactionsCompanion(categoryOverrideId: Value(categoryId)),
            );
        if (updated == 0) {
          throw ArgumentError.value(
            transactionId,
            'transactionId',
            'not found',
          );
        }
      });

  @override
  Future<Category?> byKey(String key) => (_db.select(
    _db.categories,
  )..where((c) => c.key.equals(key))).getSingleOrNull();

  @override
  Stream<Map<int, int>> watchUsage() => _db
      .customSelect(
        'SELECT COALESCE(t.category_override_id, CASE WHEN p.ask_purpose '
        "AND t.direction = 'inflow' THEN NULL ELSE COALESCE("
        'p.default_category_id, t.auto_category_id) END) AS category, '
        'COUNT(*) AS uses '
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
