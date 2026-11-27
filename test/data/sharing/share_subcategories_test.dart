import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/categories_repository.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';

import '../../helpers/share_phones.dart';

Future<Category> _named(Phone p, String name) => (p.db.select(
  p.db.categories,
)..where((c) => c.name.equals(name))).getSingle();

Future<int> _transport(Phone p) async => (await (p.db.select(
  p.db.categories,
)..where((c) => c.key.equals('transport'))).getSingle()).id;

void main() {
  test('a subcategory reaches the other phone under the same parent, '
      'parents first', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane Wairimu');
    await me.account('Cash box');
    await share(me, {jane: ShareRole.member});

    // A new parent and its subcategory travel in one file.
    final repo = DriftCategoriesRepository(me.db);
    final boda = await repo.create(
      name: 'Boda boda',
      type: CategoryType.expense,
    );
    await repo.create(
      name: 'Night rides',
      type: CategoryType.expense,
      parentId: boda,
    );
    await repo.create(
      name: 'Uber',
      type: CategoryType.expense,
      parentId: await _transport(me),
    );
    me.now += 1000;
    await me.sendTo(jane);

    final uber = await _named(jane, 'Uber');
    expect(uber.parentId, await _transport(jane));
    final night = await _named(jane, 'Night rides');
    expect(night.parentId, (await _named(jane, 'Boda boda')).id);
  });

  test('a subcategory whose parent never arrives stays, top-level', () async {
    final me = Phone('Achieng');
    final jane = Phone('Jane Wairimu');
    await me.account('Cash box');
    await share(me, {jane: ShareRole.member});

    final repo = DriftCategoriesRepository(me.db);
    final boda = await repo.create(
      name: 'Boda boda',
      type: CategoryType.expense,
    );
    await repo.create(
      name: 'Night rides',
      type: CategoryType.expense,
      parentId: boda,
    );
    // The parent is left out of the file.
    await me.db.customStatement(
      "DELETE FROM share_dirty WHERE entity = 'category' AND row_id = ?",
      [boda],
    );
    me.now += 1000;
    await me.sendTo(jane);

    final night = await _named(jane, 'Night rides');
    expect(night.parentId, isNull);
    expect(
      await (jane.db.select(
        jane.db.categories,
      )..where((c) => c.name.equals('Boda boda'))).getSingleOrNull(),
      isNull,
    );
  });
}
