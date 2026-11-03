import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';

void main() {
  test('every kind has unique keys and names, and keeps the common ones', () {
    for (final kind in SpaceKind.values) {
      final seeds = categorySeedsFor(kind);
      expect(
        seeds.map((s) => s.key).toSet(),
        hasLength(seeds.length),
        reason: kind.name,
      );
      expect(
        seeds.map((s) => categoryNameKey(s.name)).toSet(),
        hasLength(seeds.length),
        reason: kind.name,
      );
      final keys = {for (final s in seeds) s.key};
      expect(
        keys,
        containsAll(['fees_charges', 'own_transfer', 'tax']),
        reason: kind.name,
      );
      expect(keys.contains(ownerPayKey), kind.makesProfit, reason: kind.name);
    }
  });

  test('Personal and Something else use the full personal set', () {
    expect(categorySeedsFor(SpaceKind.personal), defaultCategories);
    expect(categorySeedsFor(SpaceKind.other), defaultCategories);
  });

  test('a business has sales, stock and wages, not betting or salary', () {
    final keys = {for (final s in categorySeedsFor(SpaceKind.business)) s.key};
    expect(keys, containsAll(['sales', 'stock', 'wages', ownerPayKey]));
    expect(keys, isNot(contains('betting')));
    expect(keys, isNot(contains('salary')));
  });

  test('a new database becomes a space with its own categories', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.spaceKind(), SpaceKind.personal);

    await db.becomeSpace(SpaceKind.farm);
    expect(await db.spaceKind(), SpaceKind.farm);
    final keys = {for (final c in await db.select(db.categories).get()) c.key};
    expect(keys, {for (final s in categorySeedsFor(SpaceKind.farm)) s.key});

    // Later upgrades seed the farm's set, not the personal one.
    await db.seedDefaultCategories();
    final again = await db.select(db.categories).get();
    expect(again.map((c) => c.key), isNot(contains('betting')));
  });
}
