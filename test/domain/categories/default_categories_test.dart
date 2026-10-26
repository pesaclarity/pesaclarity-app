import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
import 'package:pesaclarity/src/domain/enums.dart';

void main() {
  test('the default set has unique keys and names and every type', () {
    final keys = defaultCategories.map((c) => c.key).toSet();
    final names = defaultCategories.map((c) => categoryNameKey(c.name)).toSet();
    expect(keys, hasLength(defaultCategories.length));
    expect(names, hasLength(defaultCategories.length));
    expect(keys, isNot(contains(uncategorisedKey)));
    expect(
      defaultCategories.map((c) => c.type).toSet(),
      CategoryType.values.toSet(),
    );
    expect(
      defaultCategories.where((c) => c.isDailySpending).map((c) => c.key),
      containsAll(['groceries', 'transport', 'eating_out']),
    );
    for (final c in defaultCategories) {
      expect(cleanCategoryName(c.name), c.name);
      if (c.isDailySpending) expect(c.type, CategoryType.expense);
    }
  });

  group('missingSeeds', () {
    test('seeds everything into an empty table', () {
      expect(missingSeeds(const []), defaultCategories);
    });

    test('is idempotent', () {
      final once = [
        for (final s in missingSeeds(const [])) (key: s.key, name: s.name),
      ];
      expect(missingSeeds(once), isEmpty);
    });

    test('skips seeds the user already has by key or by name', () {
      final missing = missingSeeds(const [
        (key: 'rent', name: 'Nyumba'),
        (key: null, name: '  salary '),
      ]);
      expect(missing.map((s) => s.key), isNot(contains('rent')));
      expect(missing.map((s) => s.key), isNot(contains('salary')));
      expect(missing, hasLength(defaultCategories.length - 2));
    });
  });

  test('cleanCategoryName tidies or rejects', () {
    expect(cleanCategoryName('  Boda  boda '), 'Boda boda');
    expect(cleanCategoryName('   '), isNull);
    expect(cleanCategoryName('x' * 61), isNull);
  });
}
