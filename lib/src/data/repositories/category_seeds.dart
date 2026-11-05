import 'package:drift/drift.dart';

import '../../domain/categories/default_categories.dart';
import '../database/app_database.dart';

/// The id of [seed]'s category in [db]: found by its key, else by its name
/// (which then gets the key), else made.
Future<int> ensureCategory(AppDatabase db, CategorySeed seed) =>
    db.transaction(() async {
      final keyed = await (db.select(
        db.categories,
      )..where((c) => c.key.equals(seed.key))).getSingleOrNull();
      if (keyed != null) return keyed.id;
      final named =
          await (db.select(db.categories)
                ..where((c) => c.name.lower().equals(seed.name.toLowerCase())))
              .getSingleOrNull();
      if (named != null) {
        await (db.update(db.categories)..where((c) => c.id.equals(named.id)))
            .write(CategoriesCompanion(key: Value(seed.key)));
        return named.id;
      }
      return db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              key: Value(seed.key),
              name: seed.name,
              type: seed.type,
              isDailySpending: Value(seed.isDailySpending),
            ),
          );
    });
