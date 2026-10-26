import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('DriftInstitutionsRepository', () {
    test('selects and deselects institutions', () async {
      final repo = DriftInstitutionsRepository(db);
      expect(await repo.selectedIds(), isEmpty);

      await repo.setSelected('mpesa', selected: true);
      await repo.setSelected('kcb', selected: true);
      expect(await repo.selectedIds(), {'mpesa', 'kcb'});

      await repo.setSelected('kcb', selected: false);
      expect(await repo.selectedIds(), {'mpesa'});
    });

    test('selecting twice keeps the first selection time', () async {
      var now = DateTime.utc(2026, 10, 5);
      final repo = DriftInstitutionsRepository(db, clock: () => now);

      await repo.setSelected('mpesa', selected: true);
      now = DateTime.utc(2026, 10, 6);
      await repo.setSelected('mpesa', selected: true);

      final row = await db.select(db.selectedInstitutions).getSingle();
      expect(
        row.selectedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 5)),
        isTrue,
      );
    });

    test('deselecting an unselected institution is a no-op', () async {
      final repo = DriftInstitutionsRepository(db);
      await repo.setSelected('im_bank', selected: false);
      expect(await repo.selectedIds(), isEmpty);
    });

    test('watchSelectedIds emits each change', () async {
      final repo = DriftInstitutionsRepository(db);
      final emitted = expectLater(
        repo.watchSelectedIds(),
        emitsInOrder([
          <String>{},
          {'mpesa'},
          {'mpesa', 'im_bank'},
          {'im_bank'},
        ]),
      );

      await pumpEventQueue();
      await repo.setSelected('mpesa', selected: true);
      await pumpEventQueue();
      await repo.setSelected('im_bank', selected: true);
      await pumpEventQueue();
      await repo.setSelected('mpesa', selected: false);
      await emitted;
    });
  });

  group('DriftOnboardingRepository', () {
    test('is incomplete until marked complete', () async {
      final repo = DriftOnboardingRepository(
        db,
        clock: () => DateTime.utc(2026, 10, 26, 9),
      );
      expect(await repo.isComplete(), isFalse);

      await repo.markComplete();
      await repo.markComplete();

      expect(await repo.isComplete(), isTrue);
      final row = await db.select(db.appSettings).getSingle();
      expect(row.key, DriftOnboardingRepository.completedAtKey);
      expect(row.value, '2026-10-26T09:00:00.000Z');
    });

    test('survives reopening the database', () async {
      final raw = sqlite3.openInMemory();
      addTearDown(raw.close);
      AppDatabase open() => AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );

      final first = open();
      await DriftOnboardingRepository(first).markComplete();
      await first.close();

      final second = open();
      addTearDown(second.close);
      expect(await DriftOnboardingRepository(second).isComplete(), isTrue);
    });
  });

  test('migrates a version 1 database by adding the new tables', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    AppDatabase open() =>
        AppDatabase(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));

    // Build the current schema, then strip it back to version 1.
    final current = open();
    await current.customSelect('SELECT 1').get();
    await current.close();
    raw
      ..execute('DROP TABLE selected_institutions')
      ..execute('DROP TABLE app_settings')
      ..execute('PRAGMA user_version = 1');

    final migrated = open();
    addTearDown(migrated.close);
    await DriftInstitutionsRepository(migrated)
        .setSelected('mpesa', selected: true);
    await DriftOnboardingRepository(migrated).markComplete();

    expect(raw.select('PRAGMA user_version').single.values.single, 2);
    expect(await DriftInstitutionsRepository(migrated).selectedIds(), {
      'mpesa',
    });
  });
}
